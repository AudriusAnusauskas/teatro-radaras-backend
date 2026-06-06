require "nokogiri"
require "faraday/retry"
require "date"

module Scrapers
  class OktScheduleScraper
    BASE_URL = "https://www.okt.lt"
    REPERTOIRE_URL = "https://www.okt.lt/repertuaras/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"

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

    DATETIME_LABEL_PATTERN = /\A([a-ząčęėįšųūž]+)\s+(\d{1,2})\s*d\.?(?:\s+\S+)?\s+(\d{1,2}):(\d{2})\z/i

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    # Returns array of { production_slug:, production_url:, starts_at:, venue:, city:, ticket_url: }.
    def fetch_all
      Rails.logger.info("[OktScheduleScraper] Fetching schedule from #{REPERTOIRE_URL}")

      doc = html_doc(REPERTOIRE_URL)
      screenings = doc.css("div.home-shows__row").filter_map { |row| parse_row(row) }

      deduped = screenings.uniq { |s| [s[:production_slug], s[:starts_at], s[:ticket_url]] }
      Rails.logger.info("[OktScheduleScraper] Found #{deduped.size} screenings")
      deduped
    end

    private

    def parse_row(row)
      production_href = row.at_css('.home-shows__about a[href*="/spektakliai/"]')&.[]("href")
      slug = normalize_slug(slug_from_href(production_href))
      return nil if slug.blank?

      datetime_text = clean_text(row.at_css(".home-shows__location strong")&.text)
      parsed = parse_datetime_label(datetime_text)
      return nil unless parsed

      data_month = row["data-month"]&.to_i
      if data_month.present? && data_month != parsed[:month]
        Rails.logger.warn(
          "[OktScheduleScraper] Month mismatch for #{slug}: data-month=#{data_month}, text=#{parsed[:month]}"
        )
      end

      year = infer_year(parsed[:month])
      starts_at = build_starts_at(year, parsed[:month], parsed[:day], parsed[:hour], parsed[:minute])
      return nil unless starts_at

      city = clean_text(row["data-city"]).presence

      {
        production_slug: slug,
        production_url: canonical_production_url(slug),
        starts_at: starts_at,
        venue: extract_venue(row),
        city: city,
        ticket_url: extract_ticket_url(row)
      }
    end

    def parse_datetime_label(text)
      match = clean_text(text).match(DATETIME_LABEL_PATTERN)
      return nil unless match

      month_key = match[1].downcase
      month = LITHUANIAN_MONTHS[month_key]
      return nil unless month

      {
        month: month,
        day: match[2].to_i,
        hour: match[3].to_i,
        minute: match[4].to_i
      }
    end

    # Page has data-month but no year. Repertoire lists upcoming shows only:
    # month >= current month → this year, else next year (handles Dec→Jan rollover).
    def infer_year(month)
      Time.use_zone("Europe/Vilnius") do
        now = Time.zone.now
        month >= now.month ? now.year : now.year + 1
      end
    end

    def build_starts_at(year, month, day, hour, minute)
      Time.use_zone("Europe/Vilnius") do
        Time.zone.local(year, month, day, hour, minute).iso8601
      end
    rescue ArgumentError
      nil
    end

    def extract_venue(row)
      location = row.at_css(".home-shows__location")
      return nil unless location

      strong_text = clean_text(location.at_css("strong")&.text)
      full_text = clean_text(location.text)
      venue = full_text.sub(strong_text, "").strip
      venue.presence
    end

    def extract_ticket_url(row)
      href = row.at_css(".home-shows__purchase a[href]")&.[]("href")
      clean_text(href).presence
    end

    def slug_from_href(href)
      return nil if href.blank?

      path = URI.parse(absolute_url(href)).path
      path.split("/").reject(&:blank?).last
    end

    def normalize_slug(slug)
      slug.to_s.strip.sub(/\.+\z/, "").downcase
    end

    def canonical_production_url(slug)
      "#{BASE_URL}/spektakliai/#{normalize_slug(slug)}/"
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
