require "nokogiri"
require "faraday/retry"
require "date"

module Scrapers
  class OktCatalogScraper
    BASE_URL = "https://www.okt.lt"
    LIST_URL = "https://www.okt.lt/spektakliai/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 1.5

    RUNTIME_PREFIX_PATTERN = /\ASpektaklio trukmė:\s*/i
    TRANSLATOR_LABEL_PATTERN = /vertėj|vertė/i

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    def fetch_catalog_list
      Rails.logger.info("[OktCatalogScraper] Collecting URLs from #{LIST_URL}")
      slugs_from_list_page.map do |slug, url|
        { slug: slug, url: url }
      end
    end

    def fetch_production_detail(url)
      slug = slug_from_url(url)
      source_url = canonical_production_url(slug)
      fetch_url = absolute_url(url)
      Rails.logger.info("[OktCatalogScraper] Fetching detail from #{fetch_url}")
      doc = html_doc(fetch_url)
      hero = first_show_hero(doc)
      description_data = parse_description_section(doc)

      runtime_text = extract_runtime_text(hero)
      title = clean_text(hero&.at_css("h1.show-hero__title")&.text)

      {
        title: title,
        slug: slug,
        source_url: source_url,
        author: clean_text(hero&.at_css(".show-hero__author")&.text),
        director_name: clean_text(hero&.at_css(".show-hero__director")&.text),
        translator: description_data[:translator],
        runtime: runtime_text,
        runtime_minutes: parse_runtime_minutes(runtime_text),
        premiere_date: description_data[:premiere_date],
        description: description_data[:description],
        cast: description_data[:cast],
        creative_team: description_data[:creative_team],
        poster_url: extract_poster_url(hero)
      }
    end

    def fetch_all
      items = fetch_catalog_list

      items.filter_map.with_index do |item, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        fetch_production_detail(item[:url])
      rescue StandardError => e
        Rails.logger.error("[OktCatalogScraper] Failed #{item[:url]}: #{e.message}")
        nil
      end
    end

    private

    def slugs_from_list_page
      doc = html_doc(LIST_URL)
      slugs = {}

      doc.css(".shows-list--archive a.home-shows__row").each do |row|
        url = absolute_url(row["href"])
        slug = slug_from_url(url)
        next if slug.blank?

        slugs[slug] = url
      end

      Rails.logger.info("[OktCatalogScraper] Found #{slugs.size} productions on list page")
      slugs
    end

    def first_show_hero(doc)
      doc.at_css(".page-shows-single .show-hero:not(.show-hero--overlay)") ||
        doc.at_css(".page-shows-single .show-hero")
    end

    def extract_runtime_text(hero)
      raw = clean_text(hero&.at_css(".show-hero__runtime")&.text)
      return nil if raw.blank?

      raw.sub(RUNTIME_PREFIX_PATTERN, "").presence
    end

    def extract_poster_url(hero)
      style = hero&.[]("style")
      match = style&.match(/background-image:\s*url\(['"]?([^'")]+)['"]?\)/i)
      match ? absolute_url(match[1]) : nil
    end

    def parse_description_section(doc)
      container = doc.at_css(".page-shows-single .show-description")
      return empty_description_data unless container

      synopsis_parts = []
      creative_team = {}
      cast = []
      premiere_date = nil
      translator = nil

      container.css("p").each do |paragraph|
        if paragraph.css("strong").empty?
          text = clean_text(paragraph.text)
          synopsis_parts << text if text.present?
          next
        end

        parse_labeled_blocks(paragraph).each do |label, value|
          case label
          when /\AVaidina\z/i
            cast = parse_cast_lines(value)
          when /\APremjera\z/i
            premiere_date = parse_premiere_date(value)
          else
            if label.match?(TRANSLATOR_LABEL_PATTERN)
              translator ||= clean_text(value)
            end
            creative_team[label] = clean_text(value)
          end
        end
      end

      {
        description: synopsis_parts.join("\n\n").presence,
        cast: cast,
        creative_team: creative_team,
        premiere_date: premiere_date,
        translator: translator
      }
    end

    def parse_labeled_blocks(paragraph)
      paragraph.inner_html.split(/<strong>/i).filter_map do |chunk|
        next if chunk.blank?

        label_html, value_html = chunk.split(%r{</strong>}i, 2)
        next if value_html.nil?

        label = clean_text(Nokogiri::HTML.fragment(label_html).text)
        value = value_html.gsub(%r{<br\s*/?>}i, "\n").gsub(/<[^>]+>/, "")
        [label, value] if label.present?
      end
    end

    def parse_cast_lines(value)
      value.to_s.split("\n").flat_map do |line|
        line = clean_text(line)
        next [] if line.blank?

        if line.match?(/[–-]/)
          name = clean_text(line.split(/[–-]/, 2).last)
          name.present? ? [name] : []
        else
          [line]
        end
      end.uniq
    end

    def parse_premiere_date(text)
      return nil if text.blank?

      Date.parse(clean_text(text)).iso8601
    rescue Date::Error, ArgumentError
      nil
    end

    def parse_runtime_minutes(runtime)
      return nil if runtime.blank?

      hours = runtime[/(\d+)\s*val/i, 1].to_i
      minutes = runtime[/(\d+)\s*min/i, 1].to_i
      total = (hours * 60) + minutes
      total.positive? ? total : nil
    end

    def empty_description_data
      {
        description: nil,
        cast: [],
        creative_team: {},
        premiere_date: nil,
        translator: nil
      }
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
      escaped_href = URI::DEFAULT_PARSER.escape(href.to_s.strip)
      URI.join(BASE_URL, escaped_href).to_s
    end

    def canonical_production_url(slug)
      "#{BASE_URL}/spektakliai/#{normalize_slug(slug)}/"
    end

    def slug_from_url(url)
      normalize_slug(URI.parse(url).path.split("/").reject(&:blank?).last)
    end

    def normalize_slug(slug)
      slug.to_s.strip.downcase
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end
  end
end
