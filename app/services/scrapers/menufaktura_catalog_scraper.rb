require "nokogiri"
require "faraday/retry"
require "set"
require "uri"

module Scrapers
  class MenufakturaCatalogScraper
    BASE = "https://menufaktura.lt"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 1.5 # seconds

    # Full Lithuanian alphabet used by the menufaktura.lt review index, plus "<"
    # for titles starting with numbers/symbols.
    LETTERS = %w[A B C Č D E F G H I Į Y J K L M N O P R S Š T U V X Z Ž <].freeze

    def initialize(http: nil)
      @http = http || build_http
    end

    # Returns array of { title:, menufaktura_id: } across all letters, deduped by ID.
    def fetch_all
      by_id = {}

      LETTERS.each_with_index do |letter, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?

        fetch_letter(letter).each do |item|
          by_id[item[:menufaktura_id]] ||= item
        end
      end

      by_id.values
    end

    # Productions listed under a single letter page.
    def fetch_letter(letter)
      url = "#{BASE}/recenzijos?l=#{URI.encode_www_form_component(letter)}"
      doc = fetch_doc(url)
      return [] unless doc

      doc.css("ul.list.list-contents li.item a").filter_map do |link|
        id = menufaktura_id_from_href(link["href"])
        next unless id

        title = (link["title"].presence || link.text).to_s.strip
        next if title.blank?

        { title: title, menufaktura_id: id }
      end.uniq { |item| item[:menufaktura_id] }
    end

    private

    # href example: https://menufaktura.lt/recenzijos?spektaklis=263801
    def menufaktura_id_from_href(href)
      href.to_s[/[?&]spektaklis=(\d+)/, 1]&.to_i
    end

    def fetch_doc(url)
      Rails.logger.info("[MenufakturaCatalogScraper] Fetching #{url}")
      response = @http.get(url)
      return nil unless response.status == 200

      Nokogiri::HTML(response.body)
    rescue Faraday::Error => e
      Rails.logger.error("[MenufakturaCatalogScraper] HTTP error #{url}: #{e.message}")
      nil
    end

    def build_http
      Faraday.new do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.adapter Faraday.default_adapter
      end
    end
  end
end
