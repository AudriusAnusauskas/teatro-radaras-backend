require "nokogiri"
require "faraday/retry"

module Scrapers
  class LndtScheduleScraper
    BASE_URL = "https://www.teatras.lt"
    REPERTUARAS_URL = "https://www.teatras.lt/lt/repertuaras"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    CITY = "Vilnius"

    MONTHS = {
      "SAUSIS" => 1,
      "VASARIS" => 2,
      "KOVAS" => 3,
      "BALANDIS" => 4,
      "GEGUŽĖ" => 5,
      "BIRŽELIS" => 6,
      "LIEPA" => 7,
      "RUGPJŪTIS" => 8,
      "RUGSĖJIS" => 9,
      "SPALIS" => 10,
      "LAPKRITIS" => 11,
      "GRUODIS" => 12
    }.freeze

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    # Returns current LNDT screenings from the repertory page.
    def fetch_all
      fetch_screenings
    end

    def fetch_screenings
      Rails.logger.info("[LndtScheduleScraper] Fetching schedule from #{REPERTUARAS_URL}")

      doc = html_doc(REPERTUARAS_URL)
      screenings = []
      current_month = nil
      current_year = nil
      previous_month = nil

      schedule_nodes(doc).each do |node|
        if month_heading?(node)
          current_month = parse_month_name(node.text)
          current_year = infer_year(current_month, previous_month, current_year)
          previous_month = current_month
          next
        end

        next unless current_month && data_table?(node)

        node.css("tr").each do |row|
          screening = parse_screening_row(row, current_month, current_year)
          screenings << screening if screening
        end
      end

      Rails.logger.info("[LndtScheduleScraper] Found #{screenings.size} screenings")
      screenings
    end

    private

    def html_doc(path_or_url)
      response = @http.get(path_for(path_or_url))
      Nokogiri::HTML(response.body)
    end

    def path_for(path_or_url)
      uri = URI.parse(path_or_url)
      return path_or_url if uri.relative?

      "#{uri.path}#{uri.query ? "?#{uri.query}" : ""}"
    end

    def schedule_nodes(doc)
      doc.css('a[href="javascript:void(0)"], table')
    end

    def month_heading?(node)
      node.name == "a" && parse_month_name(node.text).present?
    end

    def parse_month_name(text)
      MONTHS[clean_text(text).upcase]
    end

    def infer_year(month_num, previous_month_num, current_year)
      today = Time.zone.today

      return month_num >= today.month ? today.year : today.year + 1 if current_year.nil?
      return current_year + 1 if previous_month_num && month_num < previous_month_num

      current_year
    end

    def data_table?(node)
      node.name == "table" && node["class"] != "month"
    end

    def parse_screening_row(row, month, year)
      cells = row.css("td, th")
      return nil if cells.size < 6

      production_link = row.at_css('a[href*="/lt/spektakliai/"]')
      return nil unless production_link

      starts_at = parse_starts_at(clean_text(cells[0].text), month, year)
      return nil unless starts_at

      path_slug = extract_slug(production_link["href"])
      source_url = absolute_url("/lt/spektakliai/#{path_slug}/") if path_slug

      {
        production_slug: path_slug,
        production_source_url: source_url,
        production_title: clean_text(production_link.text),
        starts_at: starts_at,
        venue: clean_text(cells[3].text).presence,
        city: CITY,
        ticket_url: extract_ticket_url(row)
      }
    end

    def parse_starts_at(cell_text, month, year)
      match = cell_text.match(/(\d{1,2})\s*\([^)]+\)\s*\/\s*(\d{1,2}):(\d{2})/)
      return nil unless match

      day, hour, minute = match[1..3].map(&:to_i)

      Time.use_zone("Vilnius") do
        Time.zone.local(year, month, day, hour, minute).iso8601
      end
    rescue ArgumentError
      nil
    end

    def extract_slug(href)
      match = absolute_url(href).match(%r{/lt/spektakliai/([^/]+)})
      match&.[](1)
    end

    def extract_ticket_url(row)
      row.css("a[href]").map { |link| absolute_url(link["href"]) }.find do |url|
        !url.include?("/lt/spektakliai/") && !url.include?("/lt/teatras/")
      end
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
