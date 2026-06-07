require "nokogiri"
require "faraday/retry"

module Scrapers
  class KlaipedosScheduleScraper
    BASE_URL = "https://kdt.lt"
    REPERTUARAS_URL = "https://kdt.lt/repertuaras/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3

    DISPLAY_DATE_TIME_PATTERN = /\A(\d{2})\.(\d{2})\s+(\d{1,2}):(\d{2})\z/
    PREMIERE_TITLE_PATTERN = /premjera/i

    VENUE_ALIASES = {
      "didžioji scena" => "Didžioji salė"
    }.freeze

    def initialize(http: nil, catalog_scraper: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
      @catalog_scraper = catalog_scraper
      @recon_reported = false
    end

    def fetch_all
      production_urls = collect_production_urls
      report_recon(production_urls) unless @recon_reported

      Rails.logger.info("[KlaipedosScheduleScraper] Fetching screenings from #{production_urls.size} pages")

      screenings = []
      production_urls.each_with_index do |url, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        screenings.concat(parse_screenings_from_detail(url))
      rescue StandardError => e
        Rails.logger.error("[KlaipedosScheduleScraper] Failed #{url}: #{e.message}")
      end

      deduped = screenings.uniq { |s| [s[:source_url], s[:starts_at], s[:ticket_url]] }
      Rails.logger.info("[KlaipedosScheduleScraper] Found #{deduped.size} screenings")
      deduped
    end

    private

    def collect_production_urls
      catalog_scraper.send(:collect_repertuaras_urls).uniq.sort
    end

    def catalog_scraper
      @catalog_scraper ||= KlaipedosCatalogScraper.new(http: @http)
    end

    def report_recon(production_urls)
      @recon_reported = true
      puts "\n=== KlaipedosScheduleScraper RECON ==="
      puts "Production URLs from /repertuaras/: #{production_urls.size}"
      puts "Screening selectors per detail page:"
      puts "  main: .show-list .show-item"
      puts "  extra: .others-show-list .show-item ('Taip pat rodome:')"
      puts "  hall: .show-title"
      puts "  date/time: .date (MM.DD HH:MM)"
      puts "  ticket: a[href*='bilietai.kdt.lt/kasa/seansas/'] (passthrough)"
      puts ""
    end

    def parse_screenings_from_detail(url)
      source_url = catalog_scraper.send(:normalize_detail_url, url)
      doc = html_doc(source_url)
      title = clean_title(doc.at_css("h1")&.text)
      premiere_tagged = premiere_tagged?(doc)

      doc.css(".show-list .show-item, .others-show-list .show-item").filter_map do |item|
        parse_show_item(item, source_url:, title:, is_premiere: premiere_tagged)
      end
    end

    def parse_show_item(item, source_url:, title:, is_premiere:)
      venue = normalize_venue(item.at_css(".show-title")&.text)
      date_text = clean_text(item.at_css(".date")&.text)
      ticket_url = item.at_css("a[href*='bilietai.kdt.lt/kasa/seansas/']")&.[]("href")
      starts_at = parse_starts_at(date_text)

      if venue.blank? || starts_at.blank? || ticket_url.blank?
        Rails.logger.warn(
          "[KlaipedosScheduleScraper] Skipping item on #{source_url} — " \
          "venue=#{venue.inspect}, starts_at=#{starts_at.inspect}, ticket=#{ticket_url.inspect}"
        )
        return nil
      end

      {
        source_url: source_url,
        title: title,
        starts_at: starts_at,
        venue: venue,
        ticket_url: clean_text(ticket_url),
        is_premiere: is_premiere
      }
    end

    def clean_title(text)
      clean_text(text).sub(/\APREMJERA\.?\s+/i, "")
    end

    def premiere_tagged?(doc)
      title = clean_text(doc.at_css("h1")&.text)
      sidebar = doc.at_css(".grid.grid-cols-12.bg-white")&.text.to_s
      title.match?(PREMIERE_TITLE_PATTERN) ||
        sidebar.match?(/#premiere|#premjera/i)
    end

    def parse_starts_at(date_text)
      match = date_text.match(DISPLAY_DATE_TIME_PATTERN)
      return nil unless match

      month = match[1].to_i
      day = match[2].to_i
      hour = match[3].to_i
      minute = match[4].to_i
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

    def canonical_production_url(slug)
      "#{BASE_URL}/renginiai/#{normalize_slug(slug)}/"
    end

    def slug_from_url(url)
      path = url.to_s
      path = URI.parse(path).path if path.start_with?("http")
      path.split("/").reject(&:blank?).last
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

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end

    def normalize_venue(name)
      key = clean_text(name).downcase
      VENUE_ALIASES.fetch(key, clean_text(name))
    end
  end
end
