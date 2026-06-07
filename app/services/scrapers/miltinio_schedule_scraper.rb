require "nokogiri"
require "faraday/retry"

module Scrapers
  class MiltinioScheduleScraper
    BASE_URL = "https://www.miltinioteatras.lt"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3

    KAKAVA_DATE_PATTERN = /(\p{L}+)\s+(\d{1,2})\s+\p{L}+\s+(\d{1,2}):(\d{2})/u

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

      Rails.logger.info("[MiltinioScheduleScraper] Fetching screenings from #{production_urls.size} pages")

      screenings = []
      production_urls.each_with_index do |url, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        screenings.concat(parse_screenings_from_detail(url))
      rescue StandardError => e
        Rails.logger.error("[MiltinioScheduleScraper] Failed #{url}: #{e.message}")
      end

      deduped = screenings.uniq { |s| [s[:source_url], s[:starts_at], s[:ticket_url]] }
      Rails.logger.info("[MiltinioScheduleScraper] Found #{deduped.size} screenings")
      deduped
    end

    private

    def collect_production_urls
      catalog_scraper.send(:collect_detail_urls)
    end

    def catalog_scraper
      @catalog_scraper ||= MiltinioCatalogScraper.new(http: @http)
    end

    def report_recon(production_urls)
      @recon_reported = true
      puts "\n=== MiltinioScheduleScraper RECON ==="
      puts "Production URLs (same as catalog): #{production_urls.size}"
      puts "Screening source: a[href*='kakava.lt'] on each detail page"
      puts "  starts_at: '{month-genitive} {day} {Weekday} HH:MM' (Europe/Vilnius year inference)"
      puts "  venue: production hall line from metadata"
      puts "  ticket_url: kakava.lt href (passthrough)"
      puts ""
    end

    def parse_screenings_from_detail(url)
      source_url = catalog_scraper.send(:normalize_detail_url, url)
      doc = html_doc(source_url)
      title = clean_text(doc.at_css("h1")&.text)
      lines = catalog_scraper.send(:metadata_lines, doc)
      meta = catalog_scraper.send(:parse_meta_fields, lines)
      venue = meta[:venue]

      doc.css("a[href*='kakava.lt']").filter_map do |link|
        ticket_url = clean_text(link["href"])
        starts_at = parse_starts_at_from_link_text(link.text)
        next if ticket_url.blank? || starts_at.blank?

        if venue.blank?
          Rails.logger.warn(
            "[MiltinioScheduleScraper] Missing venue for #{source_url} — using hall from page metadata"
          )
        end

        {
          source_url: source_url,
          title: title,
          starts_at: starts_at,
          venue: venue,
          ticket_url: ticket_url
        }
      end
    end

    def parse_starts_at_from_link_text(text)
      match = clean_text(text).match(KAKAVA_DATE_PATTERN)
      return nil unless match

      month_name = match[1].downcase
      month = MiltinioCatalogScraper::LITHUANIAN_MONTHS[month_name]
      return nil unless month

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

    def html_doc(path_or_url)
      response = @http.get(path_for(path_or_url))
      Nokogiri::HTML(response.body)
    end

    def path_for(path_or_url)
      uri = URI.parse(path_or_url)
      return path_or_url if uri.relative?

      uri.path
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end
  end
end
