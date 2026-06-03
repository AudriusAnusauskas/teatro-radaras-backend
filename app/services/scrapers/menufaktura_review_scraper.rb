require "nokogiri"
require "faraday/retry"
require "set"
require "date"

module Scrapers
  class MenufakturaReviewScraper
    BASE = "https://menufaktura.lt"
    PUBLICATION = "menufaktura.lt"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 2.0 # seconds — between list (pagination) page fetches
    DELAY_BETWEEN_ARTICLE_REQUESTS = 2.0 # seconds — between individual article fetches
    MAX_PAGES = 20 # safety cap for pagination

    def initialize(menufaktura_id, http: nil)
      @id = menufaktura_id
      @http = http || build_http
    end

    # Returns array of { url:, title:, author:, published_on:, body:, quote:, publication: }.
    # Flow: list pages -> article URLs -> full fetch per article (/recenzija/{slug}).
    # 7md.lt reposts are skipped (returned as nil and compacted away).
    def fetch_all
      entries = fetch_review_list

      entries.filter_map.with_index do |entry, index|
        sleep DELAY_BETWEEN_ARTICLE_REQUESTS if index.positive?
        fetch_article(entry)
      end
    end

    # List-level metadata across paginated pages.
    def fetch_review_list
      entries = []
      seen = Set.new

      (1..MAX_PAGES).each do |page|
        doc = fetch_doc(list_page_url(page))
        break unless doc

        page_entries = parse_list(doc).reject { |entry| seen.include?(entry[:url]) }
        break if page_entries.empty?

        page_entries.each { |entry| seen.add(entry[:url]) }
        entries.concat(page_entries)
        sleep DELAY_BETWEEN_REQUESTS
      end

      entries
    end

    private

    def list_page_url(page)
      if page <= 1
        "#{BASE}/recenzijos?spektaklis=#{@id}"
      else
        "#{BASE}/recenzijos/page/#{page}/?spektaklis=#{@id}"
      end
    end

    # Review list items live in li.item > div.info; the alphabetical index uses
    # the same li.item but without div.info, so requiring div.info + a.title
    # pointing at /recenzija/ cleanly isolates real reviews.
    def parse_list(doc)
      doc.css("li.item").filter_map do |li|
        info = li.at_css("div.info")
        next unless info

        link = info.at_css("a.title")
        next unless link && link["href"].to_s.include?("/recenzija/")

        {
          url: absolute_url(link["href"]),
          title: (link["title"].presence || link.text).to_s.strip,
          author: info.at_css("div.author")&.text&.strip.presence,
          published_on: parse_date(info.at_css("div.date")&.text)
        }
      end.uniq { |entry| entry[:url] }
    end

    def fetch_article(entry)
      doc = fetch_doc(entry[:url])
      return nil unless doc

      if republished_from_7md?(doc)
        Rails.logger.info("[MenufakturaReviewScraper] Skipping 7md repost: #{entry[:url]}")
        return nil
      end

      {
        url: entry[:url],
        title: entry[:title].presence || doc.at_css("h1")&.text&.strip,
        author: entry[:author] || byline_text(doc, "author"),
        published_on: entry[:published_on] || parse_date(byline_text(doc, "date")),
        body: extract_body(doc),
        quote: extract_excerpt(doc),
        publication: PUBLICATION
      }
    rescue Faraday::Error => e
      Rails.logger.error("[MenufakturaReviewScraper] HTTP error #{entry[:url]}: #{e.message}")
      nil
    end

    # The article byline (div.info) names the original source in span.source.
    # Native reviews show "menufaktura.lt"; reposts from 7md show "7md.lt".
    def republished_from_7md?(doc)
      byline = doc.css("div.info").text.to_s.downcase
      byline.include?("7md") || byline.include?("7 meno dienos")
    end

    def byline_text(doc, role)
      doc.at_css("div.info span.#{role}")&.text&.strip.presence
    end

    # Full review text lives in div.wysiwyg on the /recenzija/{slug} page
    # (~7k+ chars, no byline/nav noise). Falls back to the div.desc lead
    # paragraph only if the full body can't be extracted.
    def extract_body(doc)
      full = doc.css("div.wysiwyg").map { |node| node.text.strip }.reject(&:empty?).join("\n\n").strip
      return full if full.present?

      extract_excerpt(doc)
    end

    # Short lead paragraph — used as a fallback note/excerpt.
    def extract_excerpt(doc)
      doc.at_css("div.desc")&.text&.strip.presence
    end

    def parse_date(text)
      return nil if text.to_s.strip.empty?

      match = text[/\d{4}-\d{2}-\d{2}/]
      match ? Date.parse(match) : nil
    rescue Date::Error
      nil
    end

    def absolute_url(href)
      return href if href.to_s.start_with?("http")

      "#{BASE}#{href}"
    end

    def fetch_doc(url)
      Rails.logger.info("[MenufakturaReviewScraper] Fetching #{url}")
      response = @http.get(url)
      return nil unless response.status == 200

      Nokogiri::HTML(response.body)
    rescue Faraday::Error => e
      Rails.logger.error("[MenufakturaReviewScraper] HTTP error #{url}: #{e.message}")
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
