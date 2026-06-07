require "nokogiri"
require "faraday/retry"
require "set"

module Scrapers
  class KaunoCatalogScraper
    BASE_URL = "https://dramosteatras.lt"
    CATALOG_URL = "https://dramosteatras.lt/spektakliai/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3
    ITEMS_PER_PAGE = 12

    DIRECTOR_CREW_TITLE_PATTERN = /režisier/i
    DIRECTOR_ASSISTANT_PATTERN = /asistent/i
    DIRECTOR_SUBTITLE_PATTERN = /^\s*rež\.?\s*(.+)$/i
    TRANSLATOR_TITLE_PATTERN = /vertė|vertim/i

    CREW_TITLE_MAPPINGS = [
      { pattern: /scenografij.*kostium/i, keys: %i[costumeDesigner scenographer] },
      { pattern: /scenograf/i, keys: [:scenographer] },
      { pattern: /kostium/i, keys: [:costumeDesigner] },
      { pattern: /kompozitor/i, exclude: /asist/i, keys: [:composer] },
      { pattern: /choreograf/i, keys: [:choreographer] },
      { pattern: /vaizdo projekc/i, keys: [:videoDesigner] },
      { pattern: /švies/i, keys: [:lightingDesigner] },
      { pattern: /dramaturg/i, keys: [:dramaturg] },
      { pattern: /prodiuser/i, keys: [:producer] }
    ].freeze

    META_LABELS = {
      /trukmė/i => :runtime,
      /amžius/i => :age_rating,
      /tipas/i => :genre
    }.freeze

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    def fetch_all
      detail_urls = collect_detail_urls
      Rails.logger.info("[KaunoCatalogScraper] Fetching #{detail_urls.size} production detail pages")

      detail_urls.filter_map.with_index do |url, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        fetch_production_detail(url)
      rescue StandardError => e
        Rails.logger.error("[KaunoCatalogScraper] Failed #{url}: #{e.message}")
        nil
      end
    end

    def fetch_production_detail(url)
      slug = slug_from_url(url)
      source_url = canonical_production_url(slug)
      fetch_url = absolute_url(url)
      Rails.logger.info("[KaunoCatalogScraper] Fetching detail from #{fetch_url}")

      doc = html_doc(fetch_url)
      title = clean_text(doc.at_css(".single-show__title-section--title")&.text)
      author = clean_text(doc.at_css(".single-show__title-section--pretitle")&.text).presence
      meta = parse_meta_items(doc)
      creative_team, translator = parse_creative_team(doc)
      cast_members = parse_cast_members(doc)

      {
        source_url: source_url,
        slug: slug,
        title: title,
        author: author,
        full_title: compose_full_title(author, title),
        description: parse_description(doc),
        poster_url: extract_poster_url(doc),
        cast_members: cast_members,
        creative_team: creative_team,
        translator: translator,
        awards: parse_awards(doc),
        runtime: meta[:runtime],
        runtime_minutes: parse_runtime_minutes(meta[:runtime]),
        age_rating: meta[:age_rating],
        genre: meta[:genre],
        director: resolve_director(doc),
        status: "active",
        is_guest: false
      }
    end

    private

    def collect_detail_urls
      first_doc = html_doc(CATALOG_URL)
      page_count = determine_page_count(first_doc)
      urls = Set.new

      (1..page_count).each do |page|
        sleep DELAY_BETWEEN_REQUESTS if page > 1
        doc = page == 1 ? first_doc : html_doc(catalog_page_url(page))
        doc.css(".all-shows__item a[href*='/shows/']").each do |link|
          urls << normalize_detail_url(link["href"])
        end
      end

      urls.to_a.sort
    end

    def determine_page_count(doc)
      summary = clean_text(doc.at_css(".pagination__summary")&.text)
      if summary.present?
        total = summary.scan(/\d+/).last&.to_i
        return (total.to_f / ITEMS_PER_PAGE).ceil if total&.positive?
      end

      page_numbers = doc.css(".pagination__page-number").map { |node| node.text.to_i }.reject(&:zero?)
      page_numbers.max || 1
    end

    def catalog_page_url(page)
      return CATALOG_URL if page <= 1

      "#{BASE_URL}/spektakliai/page/#{page}/"
    end

    def parse_meta_items(doc)
      meta = {}

      doc.css(".single-show__title-section--item").each do |item|
        info_node = item.at_css(".single-show__title-section--info")
        next unless info_node

        label = clean_text(info_node.at_css(".single-show__title-section--label")&.text)
        value = extract_info_value(info_node, label)
        next if label.blank? || value.blank?

        META_LABELS.each do |pattern, key|
          meta[key] = value if label.match?(pattern)
        end
      end

      meta
    end

    def extract_info_value(info_node, label)
      clone = info_node.dup
      clone.at_css(".single-show__title-section--label")&.remove
      clean_text(clone.text).presence
    end

    def parse_description(doc)
      review = doc.at_css(".single-show__full-review-section--description-text")
      if review
        paragraphs = review.css("p").map { |p| clean_text(p.text) }.reject(&:blank?)
        return paragraphs.join("\n\n").presence if paragraphs.any?
      end

      clean_text(doc.at_css(".single-show__title-section--excerpt")&.text).presence
    end

    def extract_poster_url(doc)
      og_image = doc.at_css('meta[property="og:image"]')&.[]("content")
      return absolute_url(og_image) if og_image.present?

      img = doc.at_css(".single-show__full-review-section--image img")
      src = img&.[]("data-lazy-src") || img&.[]("src")
      absolute_url(src) if src.present?
    end

    def parse_cast_members(doc)
      doc.css(".single-show__crew-section--actor-name").map { |node| clean_text(node.text) }
          .reject(&:blank?).uniq
    end

    def parse_creative_team(doc)
      creative_team = {}
      translator = nil

      doc.css(".single-show__crew-section--other-crew").each do |block|
        title = clean_text(block.at_css(".single-show__crew-section--other-crew-title")&.text)
        members = block.css(".single-show__crew-section--other-crew-member-name")
                       .map { |node| clean_text(node.text) }.reject(&:blank?)
        next if title.blank? || members.empty?

        if title.match?(TRANSLATOR_TITLE_PATTERN)
          translator ||= members.join(", ")
          next
        end

        mapped_keys_for_title(title).each do |key|
          creative_team[key.to_s] = members.join(", ")
        end
      end

      [creative_team, translator]
    end

    def mapped_keys_for_title(title)
      CREW_TITLE_MAPPINGS.flat_map do |mapping|
        next [] unless title.match?(mapping[:pattern])
        next [] if mapping[:exclude] && title.match?(mapping[:exclude])

        mapping[:keys]
      end.uniq
    end

    def parse_awards(doc)
      doc.css(".single-show__awards-section--content-item").filter_map do |item|
        year = clean_text(item.at_css(".single-show__awards-section--content-item-year")&.text)
        clone = item.dup
        clone.at_css(".single-show__awards-section--content-item-year")&.remove
        text = clean_text(clone.text)
        next if text.blank?

        year.present? ? "#{year} – #{text}" : text
      end
    end

    def resolve_director(doc)
      from_crew = director_from_crew(doc)
      return from_crew if from_crew.present?

      from_subtitle = director_from_subtitle(doc)
      return from_subtitle if from_subtitle.present?

      nil
    end

    def director_from_crew(doc)
      doc.css(".single-show__crew-section--other-crew").each do |block|
        title = clean_text(block.at_css(".single-show__crew-section--other-crew-title")&.text)
        next if title.blank?
        next unless title.match?(DIRECTOR_CREW_TITLE_PATTERN)
        next if title.match?(DIRECTOR_ASSISTANT_PATTERN)

        member = clean_text(block.at_css(".single-show__crew-section--other-crew-member-name")&.text)
        return member if member.present?
      end

      nil
    end

    def director_from_subtitle(doc)
      subtitle = clean_text(doc.at_css(".single-show__title-section--subtitle")&.text)
      match = subtitle.match(DIRECTOR_SUBTITLE_PATTERN)
      clean_text(match[1]) if match
    end

    def compose_full_title(author, title)
      return title if author.blank?

      "#{author}. #{title}"
    end

    def parse_runtime_minutes(runtime)
      return nil if runtime.blank?

      clock_match = runtime.match(/(\d{1,2}):(\d{2})/)
      if clock_match
        return (clock_match[1].to_i * 60) + clock_match[2].to_i
      end

      hours = runtime[/(\d+)\s*val/i, 1].to_i
      minutes = runtime[/(\d+)\s*min/i, 1].to_i
      total = (hours * 60) + minutes
      total.positive? ? total : nil
    end

    def normalize_detail_url(href)
      url = absolute_url(href)
      uri = URI.parse(url)
      slug = slug_from_url(uri.path)
      canonical_production_url(slug)
    end

    def canonical_production_url(slug)
      "#{BASE_URL}/shows/#{normalize_slug(slug)}/"
    end

    def slug_from_url(url)
      path = url.to_s
      path = URI.parse(path).path if path.start_with?("http")
      normalize_slug(path.split("/").reject(&:blank?).last)
    end

    def normalize_slug(slug)
      slug.to_s.strip.downcase
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

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end
  end
end
