require "nokogiri"
require "faraday/retry"

module Scrapers
  class JaunimoTeatrasScheduleScraper
    BASE_URL = "https://jaunimoteatras.lt"
    REPERTOIRE_URL = "https://jaunimoteatras.lt/repertuaras/"
    AJAX_PATH = "/wp-admin/admin-ajax.php"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 1.5

    LITHUANIAN_MONTHS = {
      "sausio" => 1,
      "vasario" => 2,
      "kovo" => 3,
      "balandžio" => 4,
      "gegužės" => 5,
      "birželio" => 6,
      "liepos" => 7,
      "rugpjūčio" => 8,
      "rugsėjo" => 9,
      "spalio" => 10,
      "lapkričio" => 11,
      "gruodžio" => 12
    }.freeze

    DATE_LABEL_PATTERN = /\A([a-ząčęėįšųūž]+)\s+(\d{1,2})\s*d\.?\s*\z/i
    TIME_PATTERN = /\A(\d{1,2}):(\d{2})\z/

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    # Returns array of { production_slug:, production_url:, starts_at:, venue:, ticket_url: }.
    def fetch_all
      Rails.logger.info("[JaunimoTeatrasScheduleScraper] Fetching schedule from #{REPERTOIRE_URL}")

      doc = html_doc(REPERTOIRE_URL)
      months = extract_month_tabs(doc)
      screenings = []

      months.each_with_index do |month, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?

        fragment = fetch_month_fragment(month[:start_date], month[:end_date])
        year = month[:start_date][0, 4].to_i
        fragment.css(".show-list > div, div.flex[class*='min-h']").each do |card|
          screening = parse_show_card(card, year)
          screenings << screening if screening
        end
      end

      deduped = screenings.uniq { |s| [s[:production_slug], s[:starts_at], s[:venue], s[:ticket_url]] }
      Rails.logger.info("[JaunimoTeatrasScheduleScraper] Found #{deduped.size} screenings")
      deduped
    end

    private

    def extract_month_tabs(doc)
      doc.css(".repertoire-months__item[data-start-date][data-end-date]").filter_map do |tab|
        start_date = tab["data-start-date"]
        end_date = tab["data-end-date"]
        next if start_date.blank? || end_date.blank?

        {
          label: clean_text(tab.text),
          start_date: start_date,
          end_date: end_date
        }
      end
    end

    def fetch_month_fragment(start_date, end_date)
      Rails.logger.info(
        "[JaunimoTeatrasScheduleScraper] Fetching month #{start_date}..#{end_date} via admin-ajax"
      )

      response = @http.post(AJAX_PATH) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          action: "repertoire_month_change",
          start_date: start_date,
          end_date: end_date
        )
      end

      Nokogiri::HTML.fragment(response.body)
    end

    def parse_show_card(card, year)
      production_link = card.at_css('a[href*="/spektakliai/"][class*="heading-2"]') ||
                        card.at_css('a[href*="/spektakliai/"]')
      return nil unless production_link

      slug = slug_from_href(production_link["href"])
      return nil if slug.blank?

      date_label = card.at_css("h3.text-secondary")&.text ||
                   card.css("h3[class*='text-secondary']").map(&:text).find { |t| date_label_text?(t) }
      show_date = parse_lithuanian_date(date_label, year)
      return nil unless show_date

      values = labeled_values(card)
      starts_at = parse_starts_at(show_date, values["Laikas"])
      return nil unless starts_at

      {
        production_slug: slug,
        production_url: absolute_url("/spektakliai/#{slug}/"),
        starts_at: starts_at,
        venue: values["Vieta"].presence,
        ticket_url: extract_ticket_url(card)
      }
    end

    def labeled_values(card)
      label_lists = card.css("ul.body-2")
      return {} if label_lists.size < 2

      labels = label_lists[0].css("li").map { |li| clean_text(li.text) }
      values = label_lists[1].css("li").map { |li| clean_text(li.text) }

      labels.each_with_index.to_h do |label, index|
        key = label.delete_suffix(":")
        [key, values[index]]
      end
    end

    def parse_lithuanian_date(text, year)
      match = clean_text(text).match(DATE_LABEL_PATTERN)
      return nil unless match

      month_key = match[1].downcase
      month = LITHUANIAN_MONTHS[month_key]
      return nil unless month

      day = match[2].to_i
      Date.new(year, month, day)
    rescue Date::Error, ArgumentError
      nil
    end

    def parse_starts_at(show_date, time_text)
      match = clean_text(time_text).match(TIME_PATTERN)
      return nil unless match

      hour, minute = match[1..2].map(&:to_i)

      Time.use_zone("Europe/Vilnius") do
        Time.zone.local(show_date.year, show_date.month, show_date.day, hour, minute).iso8601
      end
    rescue ArgumentError
      nil
    end

    def extract_ticket_url(card)
      urls = card.css('a.animated-button[href], a[href*="bilietai.lt"]').filter_map do |link|
        href = link["href"]
        next if href.blank?

        absolute_url(href) if href.include?("bilietai.lt")
      end

      urls.uniq.first
    end

    def date_label_text?(text)
      clean_text(text).match?(DATE_LABEL_PATTERN)
    end

    def slug_from_href(href)
      path = URI.parse(absolute_url(href)).path
      match = path.match(%r{/spektakliai/([^/]+)/?})
      match&.[](1)
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
      escaped_href = URI::DEFAULT_PARSER.escape(href.to_s)
      URI.join(BASE_URL, escaped_href).to_s
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end
  end
end
