require "erb"

module Scrapers
  class SevenmdProductionTagScraper
    BASE = "https://www.7md.lt"
    USER_AGENT = "Mozilla/5.0 TeatroRadaras/1.0"

    # production_title example: "Quanta" or "Lietuvių mirties pranešimai. Vieno spektaklio istorija"
    # Returns array of article URLs (or [] if tag page missing/empty)
    def fetch_article_urls(production_title)
      tag_url = build_tag_url(production_title)
      Rails.logger.info("[SevenmdProductionTagScraper] Fetching: #{tag_url}")

      response = Faraday.get(tag_url) do |req|
        req.headers["User-Agent"] = USER_AGENT
        req.options.timeout = 30
      end
      return [] unless response.status == 200

      doc = Nokogiri::HTML(response.body)
      doc.css("a[href]").map { |a| a["href"] }
         .select { |href| href.to_s.match?(%r{/(teatras|muzika|sokis)/\d{4}-\d{2}-\d{2}/}) }
         .map { |href| href.start_with?("http") ? href : "#{BASE}#{href}" }
         .uniq
    rescue StandardError => e
      Rails.logger.error("[SevenmdProductionTagScraper] Error for '#{production_title}': #{e.message}")
      []
    end

    private

    def build_tag_url(title)
      # 7md tag format: spaces → +, URL-encode special chars
      encoded = title.gsub(" ", "+")
      encoded = ERB::Util.url_encode(encoded).gsub("%2B", "+")
      "#{BASE}/tag/#{encoded}"
    end
  end
end
