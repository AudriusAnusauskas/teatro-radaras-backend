require "date"
require "nokogiri"
require "faraday/retry"
require "uri"

module Scrapers
  class SevenmdReviewScraper
    BASE = "https://www.7md.lt"
    PUBLICATION = "7 meno dienos"
    USER_AGENT = "Mozilla/5.0 TeatroRadaras/1.0"

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    def fetch_recent(category: "teatras", max_pages: 5)
      urls = []

      (1..max_pages).each do |page|
        page_urls = fetch_listing_urls(category: category, page: page)
        break if page_urls.empty?

        urls.concat(page_urls)
      end

      urls.uniq.map { |url| fetch_article(url) }.compact
    end

    def fetch_listing_urls(category: "teatras", page: 1)
      url = page == 1 ? "#{BASE}/#{category}" : "#{BASE}/#{category}/p-#{page}"
      Rails.logger.info("[SevenmdReviewScraper] Fetching listing: #{url}")

      doc = fetch_html(url)
      return [] unless doc

      doc.css(%(a[href*="/#{category}/"])).map { |a| a["href"] }
         .select { |href| href.match?(%r{/#{category}/\d{4}-\d{2}-\d{2}/}) }
         .map { |href| absolute_url(href) }
         .uniq
    end

    def fetch_article(url)
      Rails.logger.info("[SevenmdReviewScraper] Fetching article: #{url}")
      doc = fetch_html(url)
      return nil unless doc

      {
        publication: PUBLICATION,
        url: url,
        title: extract_title(doc),
        subtitle: extract_subtitle(doc),
        author: extract_author(doc),
        published_at: extract_date(url),
        issue: extract_issue(doc),
        body_excerpt: extract_body_excerpt(doc),
        tags: extract_tags(doc)
      }
    rescue StandardError => e
      Rails.logger.error("[SevenmdReviewScraper] Error fetching #{url}: #{e.message}")
      nil
    end

    private

    def fetch_html(url)
      response = @http.get(path_for(url))
      return nil unless response.status == 200

      Nokogiri::HTML(response.body)
    rescue Faraday::Error => e
      Rails.logger.error("[SevenmdReviewScraper] HTTP error for #{url}: #{e.message}")
      nil
    end

    def path_for(url)
      uri = URI.parse(url)
      return url if uri.relative?

      "#{uri.path}#{uri.query ? "?#{uri.query}" : ""}"
    end

    def absolute_url(href)
      return href if href.start_with?("http")

      URI.join(BASE, href).to_s
    end

    def extract_title(doc)
      doc.at_css("h1")&.text&.strip
    end

    def extract_subtitle(doc)
      doc.at_css("h3")&.text&.strip
    end

    def extract_author(doc)
      doc.at_css(%(a[href*="/autorius/"]))&.text&.strip
    end

    def extract_date(url)
      match = url.match(%r{/(\d{4}-\d{2}-\d{2})/})
      match ? Date.parse(match[1]) : nil
    end

    def extract_issue(doc)
      match = doc.text.match(/Nr\.\s*\d+\s*\(\d+\),?\s*\d{4}-\d{2}-\d{2}/)
      match&.[](0)&.strip
    end

    def extract_body_excerpt(doc)
      paragraphs = doc.css("p").map { |p| p.text.strip }.select { |text| text.length > 50 }
      paragraphs.first(3).join("\n\n").strip[0..500]
    end

    def extract_tags(doc)
      doc.css(%(a[href*="/tag/"]))
         .map { |a| a.text.strip }
         .reject(&:empty?)
         .uniq
    end
  end
end
