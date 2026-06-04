require "nokogiri"
require "faraday/retry"
require "date"

module Scrapers
  class JaunimoTeatrasCatalogScraper
    BASE_URL = "https://jaunimoteatras.lt"
    LIST_URL = "https://jaunimoteatras.lt/spektakliai/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 1.5

    DIRECTOR_LABEL_PATTERN = /\ARežisierius|Režisierė|Režisieriai\z/i
    AGE_RATING_PATTERN = /Žiūrovai į spektaklį įleidžiami nuo (\d+)\s*metų/i

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    # Returns array of { title:, slug:, url:, author:, director_name:, poster_url: }.
    def fetch_catalog_list
      Rails.logger.info("[JaunimoTeatrasCatalogScraper] Fetching catalog from #{LIST_URL}")
      doc = html_doc(LIST_URL)

      doc.css('a.block.text-white.group').filter_map do |link|
        url = absolute_url(link["href"])
        next unless production_detail_url?(url)

        parse_list_card(link, url)
      end.uniq { |item| item[:slug] }
    end

    # Returns full production hash for one detail URL.
    def fetch_production_detail(url)
      Rails.logger.info("[JaunimoTeatrasCatalogScraper] Fetching detail from #{url}")
      doc = html_doc(url)
      meta = metadata_grids(doc)

      title = clean_text(doc.at_css("h2.heading-1")&.text)
      warn_missing("title", url) if title.blank?

      description = extract_description(doc)
      age_source = [description, meta.values, doc.css("div.prose").map(&:text)].flatten.join("\n")

      {
        title: title,
        slug: slug_from_url(url),
        source_url: canonical_url(url),
        author: clean_text(doc.at_css("h3.body-2.mb-3.text-white")&.text).presence,
        director_name: director_from_meta(meta) || director_from_grid(doc),
        cast: parse_cast_from_doc(doc),
        runtime: meta["Trukmė"],
        runtime_minutes: parse_runtime_minutes(meta["Trukmė"]),
        premiere_date: parse_premiere_date(meta["Premjera"]),
        description: description,
        age_rating: extract_age_rating(age_source),
        poster_url: extract_detail_poster_url(doc, url)
      }
    end

    # List page → per-production detail fetch with polite delay.
    def fetch_all
      fetch_catalog_list.filter_map.with_index do |item, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        fetch_production_detail(item[:url])
      rescue StandardError => e
        Rails.logger.error("[JaunimoTeatrasCatalogScraper] Failed #{item[:url]}: #{e.message}")
        nil
      end
    end

    private

    def parse_list_card(link, url)
      overlay = link.at_css("div.body-2.absolute") || link

      title = clean_text(overlay.at_css("h3.mb-3.heading-2")&.text).presence ||
              clean_text(link.at_css("h2.heading-3")&.text)
      warn_missing("title", url) if title.blank?

      author_h3 = overlay.css("h3").find do |h|
        classes = h["class"].to_s
        !classes.include?("heading-2") && !classes.include?("body-2")
      end

      {
        title: title,
        slug: slug_from_url(url),
        url: url,
        author: clean_text(author_h3&.text).presence,
        director_name: extract_list_director(overlay),
        poster_url: extract_list_poster_url(link)
      }
    end

    def extract_list_director(overlay)
      dir_node = overlay.at_css("h3.body-2.mb-3")
      return nil unless dir_node

      text = clean_text(dir_node.text)
      text.sub(/\ARežisierius\s*/i, "")
          .sub(/\ARežisierė\s*/i, "")
          .sub(/\ARežisieriai\s*/i, "")
          .strip
          .presence
    end

    def extract_list_poster_url(link)
      src = link.at_css("img")&.[]("src")
      src ? absolute_url(src) : nil
    end

    def metadata_grids(doc)
      doc.css("div.grid.grid-cols-2").each_with_object({}) do |grid, meta|
        label = grid_label(grid)
        next if label.blank?

        meta[label] = grid_value_text(grid)
      end
    end

    def grid_label(grid)
      label_span = grid.css("span").find { |s| s["class"].to_s.include?("mr-2.5") }
      clean_text(label_span&.text)
    end

    def grid_value_text(grid)
      value_col = grid.at_css("div.flex-col")
      return clean_text(value_col.text) if value_col

      value_span = grid.css("span").reject { |s| s["class"].to_s.include?("mr-2.5") }.first
      clean_text(value_span&.text)
    end

    def director_from_meta(meta)
      entry = meta.find { |label, _| label.match?(DIRECTOR_LABEL_PATTERN) }
      entry&.last&.presence
    end

    def director_from_grid(doc)
      grid = doc.css("div.grid.grid-cols-2").find { |node| grid_label(node).match?(DIRECTOR_LABEL_PATTERN) }
      return nil unless grid

      grid_value_text(grid).presence
    end

    def parse_cast_from_doc(doc)
      cast_grid = doc.css("div.grid.grid-cols-2").find { |node| grid_label(node) == "Vaidina" }
      return [] unless cast_grid

      container = cast_grid.at_css("div.flex-col") || cast_grid
      names = container.children.filter_map do |child|
        next unless %w[a span].include?(child.name)

        clean_text(child.text).presence
      end

      names.uniq
    end

    def extract_description(doc)
      article = doc.at_css("article.prose")
      return nil unless article

      lines = []
      article.css("p").each do |p|
        text = clean_text(p.text)
        break if text.match?(/\ASpektaklio recenzijos\z/i)
        break if p.at_css("strong")&.text.to_s.include?("Spektaklio recenzijos")

        lines << text if text.present?
      end

      clean_text(lines.join("\n\n")).presence
    end

    def extract_age_rating(text)
      match = text.to_s.match(AGE_RATING_PATTERN)
      return nil unless match

      "N-#{match[1]}"
    end

    def parse_premiere_date(text)
      return nil if text.blank?

      cleaned = text.strip.gsub(/[\s.]+/, "-")
      Date.parse(cleaned).iso8601
    rescue Date::Error, ArgumentError
      nil
    end

    # Same Lithuanian format as LNDtCatalogScraper: "5 val." → 300, "1 val. 30 min." → 90.
    def parse_runtime_minutes(runtime)
      return nil if runtime.blank?

      hours = runtime[/(\d+)\s*val/i, 1].to_i
      minutes = runtime[/(\d+)\s*min/i, 1].to_i
      total = (hours * 60) + minutes
      total.positive? ? total : nil
    end

    def extract_detail_poster_url(doc, url)
      img = doc.at_css(".single-swiper-desktop .swiper-slide img") ||
            doc.at_css(".single-swiper-mobile .swiper-slide img") ||
            doc.at_css(".swiper-slide img")
      src = img&.[]("src")
      warn_missing("poster_url", url) if src.blank?

      src ? absolute_url(src) : nil
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

    def canonical_url(url)
      parsed = URI.parse(url)
      parsed.fragment = nil
      parsed.query = nil
      parsed.to_s
    end

    def production_detail_url?(url)
      path = URI.parse(url).path
      path.match?(%r{\A/spektakliai/[^/]+/?\z}) && path != "/spektakliai/"
    end

    def slug_from_url(url)
      URI.parse(url).path.split("/").reject(&:blank?).last
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end

    def warn_missing(field, url)
      Rails.logger.warn("[JaunimoTeatrasCatalogScraper] Missing field '#{field}' for #{url}")
    end
  end
end
