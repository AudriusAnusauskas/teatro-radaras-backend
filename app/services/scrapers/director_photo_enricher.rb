require "nokogiri"
require "faraday/retry"

module Scrapers
  class DirectorPhotoEnricher
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3
    PHOTO_CREDIT = "Lietuvos nacionalinis dramos teatras"
    CATALOG_IMG_SELECTOR = 'img[src*="/uploads/img/catalog/"]'
    TEATRAS_BASE_URL = "https://www.teatras.lt"

    def initialize(http: nil)
      @http = http || Faraday.new do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    def enrich!(dry_run: false)
      results = { updated: 0, skipped: 0, not_found: 0, errors: [] }

      candidates.each_with_index do |director, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        process_director(director, dry_run:, results:)
      rescue StandardError => e
        Rails.logger.error("[DirectorPhotoEnricher] Failed #{director.name}: #{e.message}")
        results[:errors] << { name: director.name, source_url: director.source_url, error: e.message }
      end

      results
    end

    private

    def candidates
      Director.where.not(source_url: [nil, ""])
              .where("source_url LIKE ?", "%teatras.lt%")
              .where(photo_url: [nil, ""])
              .order(:name)
    end

    def process_director(director, dry_run:, results:)
      if director.photo_url.present?
        results[:skipped] += 1
        return
      end

      photo_url = extract_photo_url(director.source_url)

      if photo_url.blank?
        Rails.logger.warn("[DirectorPhotoEnricher] no photo: #{director.name} (#{director.source_url})")
        results[:not_found] += 1
        return
      end

      if dry_run
        puts "[DRY RUN] #{director.name} → photo_url=#{photo_url}"
      else
        director.update!(photo_url: photo_url, photo_credit: PHOTO_CREDIT)
      end

      results[:updated] += 1
    end

    def extract_photo_url(source_url)
      doc = Nokogiri::HTML(fetch_html(source_url))
      src = doc.at_css(CATALOG_IMG_SELECTOR)&.[]("src")
      return nil if src.blank?

      absolute_url(src)
    end

    def fetch_html(url)
      response = @http.get(normalize_fetch_url(url))
      response.body
    end

    # Trailing slash on person URLs can redirect to the generic listing page.
    def normalize_fetch_url(url)
      uri = URI.parse(url)
      path = uri.path.sub(%r{/\z}, "")
      query = uri.query ? "?#{uri.query}" : ""
      "#{uri.scheme}://#{uri.host}#{path}#{query}"
    end

    def absolute_url(src)
      return src if src.start_with?("http")

      URI.join(TEATRAS_BASE_URL, src).to_s
    end
  end
end
