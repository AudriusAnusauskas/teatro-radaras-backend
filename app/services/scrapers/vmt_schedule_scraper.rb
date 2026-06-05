require "nokogiri"
require "faraday/retry"
require "date"

module Scrapers
  class VmtScheduleScraper
    BASE_URL = "https://www.vmt.lt"
    REPERTOIRE_URL = "https://www.vmt.lt/repertuaras"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    SKIP_CATEGORY_TAGS = %w[Renginiai Ekskursija].freeze
    TIME_PATTERN = /(\d{1,2}):(\d{2})/

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    # Returns array of { production_slug:, production_url:, starts_at:, venue:, ticket_url: }.
    def fetch_all
      Rails.logger.info("[VmtScheduleScraper] Fetching schedule from #{REPERTOIRE_URL}")

      doc = html_doc(REPERTOIRE_URL)
      screenings = doc.css("div.event").filter_map { |event| parse_event(event) }

      deduped = screenings.uniq { |s| [s[:production_slug], s[:starts_at], s[:ticket_url]] }
      Rails.logger.info("[VmtScheduleScraper] Found #{deduped.size} screenings")
      deduped
    end

    private

    def parse_event(event)
      category = clean_text(event.at_css(".row-cta span.tag")&.text)
      if SKIP_CATEGORY_TAGS.include?(category)
        Rails.logger.info("[VmtScheduleScraper] Skipping #{category} event on #{event['data-event-date']}")
        return nil
      end

      production_href = event.at_css('a.sh[href*="/spektakliai/"]')&.[]("href")
      slug = normalize_slug(slug_from_href(production_href))
      return nil if slug.blank?

      starts_at = parse_starts_at(event["data-event-date"], event.at_css(".row-cta .name")&.text)
      return nil unless starts_at

      {
        production_slug: slug,
        production_url: absolute_url("/spektakliai/#{slug}"),
        starts_at: starts_at,
        venue: nil,
        ticket_url: extract_ticket_url(event)
      }
    end

    def parse_starts_at(date_string, name_text)
      return nil if date_string.blank?

      show_date = Date.iso8601(date_string)
      match = clean_text(name_text).match(TIME_PATTERN)
      return nil unless match

      hour, minute = match[1..2].map(&:to_i)

      Time.use_zone("Europe/Vilnius") do
        Time.zone.local(show_date.year, show_date.month, show_date.day, hour, minute).iso8601
      end
    rescue Date::Error, ArgumentError
      nil
    end

    def extract_ticket_url(event)
      link = event.at_css('.row-cta a.ticket[href*="bilietai.lt"]') ||
             event.at_css('.row-cta a[href*="bilietai.lt"]')
      href = link&.[]("href")
      href.presence
    end

    def slug_from_href(href)
      return nil if href.blank?

      path = URI.parse(absolute_url(href)).path
      path.split("/").reject(&:blank?).last
    end

    def normalize_slug(slug)
      slug.to_s.strip.sub(/\.+\z/, "").downcase
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
