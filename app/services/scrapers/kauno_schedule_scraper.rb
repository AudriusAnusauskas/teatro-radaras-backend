require "nokogiri"
require "faraday/retry"

module Scrapers
  class KaunoScheduleScraper
    BASE_URL = "https://dramosteatras.lt"
    SCHEDULE_URL = "https://dramosteatras.lt/repertuaras-ir-bilietai/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3
    ITEMS_PER_PAGE = 12

    ITEM_SELECTORS = [
      ".all-shows__item",
      ".shows-slider__item"
    ].freeze

    DATE_SELECTORS = [
      ".all-shows__item-date--date",
      ".shows-slider__item-date--date"
    ].freeze

    TIME_SELECTORS = [
      ".all-shows__item-date--time",
      ".shows-slider__item-date--time"
    ].freeze

    DISPLAY_DATE_PATTERN = /\A(\d{2})\.(\d{2})\z/
    DISPLAY_TIME_PATTERN = /(\d{1,2}):(\d{2})/
    PREMIERE_LABEL_PATTERN = /premj/i

    def initialize(http: nil)
      # dramosteatras.lt omits the intermediate cert; read-only public HTML scrape only.
      @http = http || Faraday.new(url: BASE_URL, ssl: { verify: false }) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
      @recon_reported = false
    end

    def fetch_all
      first_doc = html_doc(SCHEDULE_URL)
      report_recon(first_doc) unless @recon_reported

      page_count = determine_page_count(first_doc)
      Rails.logger.info("[KaunoScheduleScraper] Paginating schedule across #{page_count} page(s)")

      all_screenings = []
      (1..page_count).each do |page|
        sleep DELAY_BETWEEN_REQUESTS if page > 1
        doc = page == 1 ? first_doc : html_doc(schedule_page_url(page))
        schedule_items(doc).each do |item|
          parsed = parse_item(item)
          all_screenings << parsed if parsed
        end
      end

      deduped = all_screenings.uniq { |s| [s[:slug], s[:starts_at], s[:ticket_url]] }
      Rails.logger.info(
        "[KaunoScheduleScraper] Found #{deduped.size} screenings across #{page_count} page(s)"
      )
      deduped
    end

    def report_recon(doc)
      @recon_reported = true

      counts = ITEM_SELECTORS.to_h { |selector| [selector, doc.css(selector).size] }
      primary_selector = ITEM_SELECTORS.find { |selector| counts[selector].positive? } || ITEM_SELECTORS.first
      sample = doc.at_css(primary_selector)

      summary = clean_text(doc.at_css(".pagination__summary")&.text)
      page_count = determine_page_count(doc)

      puts "[KaunoScheduleScraper RECON] Schedule URL: #{SCHEDULE_URL}"
      puts "[KaunoScheduleScraper RECON] Pagination: #{summary.inspect} (#{page_count} page(s))"
      ITEM_SELECTORS.each do |selector|
        puts "[KaunoScheduleScraper RECON] #{selector}: #{counts[selector]} items"
      end
      puts "[KaunoScheduleScraper RECON] Primary container: #{primary_selector}"

      if sample
        date_node = DATE_SELECTORS.lazy.map { |sel| sample.at_css(sel) }.find(&:itself)
        time_node = TIME_SELECTORS.lazy.map { |sel| sample.at_css(sel) }.find(&:itself)
        show_link = sample.css("a[href*='/shows/']").map { |a| a["href"] }.first
        ticket_link = sample.css("a[href*='koobin.com']").map { |a| a["href"] }
                             .reject { |href| href.include?("action=PU_ident_unica") }.first
        label_text = clean_text(sample.at_css("[class*='label-holder']")&.text)

        puts "[KaunoScheduleScraper RECON] Date selector value: #{clean_text(date_node&.text).inspect}"
        puts "[KaunoScheduleScraper RECON] Time selector value: #{clean_text(time_node&.text).inspect}"
        puts "[KaunoScheduleScraper RECON] Show link: #{show_link}"
        puts "[KaunoScheduleScraper RECON] Ticket link: #{ticket_link}"
        puts "[KaunoScheduleScraper RECON] Label/premiere sample: #{label_text.inspect}"
      else
        puts "[KaunoScheduleScraper RECON] No schedule items found"
      end
    end

    private

    def determine_page_count(doc)
      summary = clean_text(doc.at_css(".pagination__summary")&.text)
      if summary.present?
        total = summary.scan(/\d+/).last&.to_i
        return (total.to_f / ITEMS_PER_PAGE).ceil if total&.positive?
      end

      page_numbers = doc.css(".pagination__page-number").map { |node| node.text.to_i }.reject(&:zero?)
      page_numbers.max || 1
    end

    def schedule_page_url(page)
      return SCHEDULE_URL if page <= 1

      "#{BASE_URL}/repertuaras-ir-bilietai/page/#{page}/"
    end

    def schedule_items(doc)
      ITEM_SELECTORS.flat_map { |selector| doc.css(selector) }.uniq
    end

    def parse_item(item)
      slug = extract_slug(item)
      display_date = extract_display_date(item)
      starts_at = parse_starts_at_from_display(item)
      ticket_url = extract_ticket_url(item)

      if slug.blank? || starts_at.blank?
        Rails.logger.warn(
          "[KaunoScheduleScraper] Skipping item — slug=#{slug.inspect}, display_date=#{display_date.inspect}, " \
          "starts_at=#{starts_at.inspect}, ticket=#{ticket_url.inspect}"
        )
        return nil
      end

      {
        slug: slug,
        source_url: canonical_production_url(slug),
        display_date: display_date,
        starts_at: starts_at,
        ticket_url: ticket_url,
        is_premiere: premiere?(item)
      }
    end

    def extract_slug(item)
      href = item.css("a[href*='/shows/']").map { |a| a["href"] }.find { |url| url.include?("/shows/") }
      slug_from_url(href)
    end

    def extract_ticket_url(item)
      # Passthrough only — koobin URLs are often stale; never derive starts_at from them.
      item.css("a[href*='koobin.com']").map { |a| a["href"] }
          .map { |href| clean_text(href) }
          .reject { |href| href.blank? || href.include?("action=PU_ident_unica") }
          .first
    end

    def extract_display_date(item)
      DATE_SELECTORS.lazy.map { |sel| clean_text(item.at_css(sel)&.text) }.find(&:present?)
    end

    def parse_starts_at_from_display(item)
      date_text = DATE_SELECTORS.lazy.map { |sel| clean_text(item.at_css(sel)&.text) }.find(&:present?)
      time_text = TIME_SELECTORS.lazy.map { |sel| clean_text(item.at_css(sel)&.text) }.find(&:present?)
      return nil if date_text.blank? || time_text.blank?

      date_match = date_text.match(DISPLAY_DATE_PATTERN)
      time_match = time_text.match(DISPLAY_TIME_PATTERN)
      return nil unless date_match && time_match

      month = date_match[1].to_i
      day = date_match[2].to_i
      hour = time_match[1].to_i
      minute = time_match[2].to_i
      year = infer_year(month)

      build_starts_at(year, month, day, hour, minute)
    end

    def infer_year(month)
      Time.use_zone("Europe/Vilnius") do
        now = Time.zone.now
        month < now.month ? now.year + 1 : now.year
      end
    end

    def build_starts_at(year, month, day, hour, minute)
      Time.use_zone("Europe/Vilnius") do
        Time.zone.local(year, month, day, hour, minute)
      end
    rescue ArgumentError
      nil
    end

    def premiere?(item)
      label = clean_text(item.at_css("[class*='label-holder']")&.text)
      label.present? && label.match?(PREMIERE_LABEL_PATTERN)
    end

    def canonical_production_url(slug)
      "#{BASE_URL}/shows/#{normalize_slug(slug)}/"
    end

    def slug_from_url(href)
      return nil if href.blank?

      path = URI.parse(absolute_url(href)).path
      normalize_slug(path.split("/").reject(&:blank?).last)
    end

    def normalize_slug(slug)
      slug.to_s.strip.downcase
    end

    def html_doc(path_or_url)
      response = @http.get(path_for(path_or_url))
      Nokogiri::HTML(response.body)
    end

    def path_for(path_or_url)
      uri = URI.parse(path_or_url)
      return path_or_url if uri.relative?

      "#{uri.path}#{uri.query ? "?#{uri.query}" : ""}"
    end

    def absolute_url(href)
      escaped_href = URI::DEFAULT_PARSER.escape(href.to_s.strip)
      URI.join(BASE_URL, escaped_href).to_s
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end
  end
end
