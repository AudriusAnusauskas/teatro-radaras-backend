require "nokogiri"
require "faraday/retry"
require "set"

module Scrapers
  class KlaipedosCatalogScraper
    BASE_URL = "https://kdt.lt"
    REPERTUARAS_URL = "https://kdt.lt/repertuaras/"
    SITEMAP_URLS = [
      "https://kdt.lt/events-sitemap.xml",
      "https://kdt.lt/events-sitemap2.xml"
    ].freeze
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3

    KDT_ORGANIZER_PATTERN = /klaipėdos dramos teatras/i
    GUEST_COUNTRY_IN_TITLE_PATTERN = /\|\s*[A-ZĄČĘĖĮŠŲŪŽ][A-ZĄČĘĖĮŠŲŪŽa-ząčęėįšųūž\s]+\z/
    OTHER_EVENT_TAG_PATTERN = /#Kiti renginiai/i
    SPEKTAKLIAI_TAG_PATTERN = /#spektakliai/i

    DIRECTOR_LABEL_PATTERN = /REŽISIER/i
    DIRECTOR_EXCLUDE_PATTERN = /PADĖJĖJ|ASISTENT/i
    AUTHOR_LABEL_PATTERN = /AUTORIUS/i
    TRANSLATOR_LABEL_PATTERN = /VERTĖ|VERTIMAS/i
    CAST_LABEL_PATTERN = /VAIDINA|EDUKACINĖS PROGRAMOS VEIKĖJAI/i
    CAST_MARKER_LINE = /\A(?:vaidina:?|edukacinės programos veikėjai:)/i
    ROLE_ACTOR_SEPARATOR = /\s[–—-]\s/
    FLIKO_POSTER_PATTERN = %r{/fliko-api/}i
    CONTENT_POSTER_IMG_SELECTOR = "div.relative.col-span-full.overflow-hidden img, " \
                                  ".tribe-events-single-event-description img, .tribe-events-content img"
    PREMIERE_LABEL_PATTERN = /PREMJERA/i
    GENRE_LINE_PATTERN = /\A\d+\s+DALIŲ\s+/i

    CREW_LABEL_MAPPINGS = [
      { pattern: /SCENOGRAF/i, keys: [:scenographer] },
      { pattern: /KOSTIUM/i, keys: [:costumeDesigner] },
      { pattern: /ŠVIES/i, keys: [:lightingDesigner] },
      { pattern: /KOMPOZITOR/i, keys: [:composer] },
      { pattern: /CHOREOGRAF/i, keys: [:choreographer] }
    ].freeze

    TOP_LEVEL_RENGINIAI_URL = %r{\Ahttps://kdt\.lt/renginiai/[^/]+/?\z}i

    VENUE_ALIASES = {
      "didžioji scena" => "Didžioji salė"
    }.freeze

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
      @recon_reported = false
    end

    def fetch_all
      detail_urls = collect_detail_urls
      report_recon(detail_urls) unless @recon_reported

      Rails.logger.info("[KlaipedosCatalogScraper] Fetching #{detail_urls.size} production detail pages")

      detail_urls.filter_map.with_index do |url, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        fetch_production_detail(url)
      rescue StandardError => e
        Rails.logger.error("[KlaipedosCatalogScraper] Failed #{url}: #{e.message}")
        nil
      end
    end

    def fetch_production_detail(url)
      source_url = normalize_detail_url(url)
      slug = slug_from_url(source_url)
      doc = html_doc(source_url)

      unless theatre_production?(doc)
        Rails.logger.info("[KlaipedosCatalogScraper] Skipping non-theatre event: #{slug}")
        return nil
      end

      credits = parse_credit_paragraphs(doc)
      title = clean_title(doc.at_css("h1")&.text)
      director = resolve_director(credits)
      if director.blank?
        Rails.logger.warn("[KlaipedosCatalogScraper] SKIP (no director): #{slug}")
        return nil
      end

      organizer = parse_organizer(doc)
      meta = parse_show_meta(doc)

      {
        source_url: source_url,
        slug: slug,
        title: title,
        author: credit_value(credits, AUTHOR_LABEL_PATTERN, prefer: /PJESĖS AUTORIUS/i),
        translator: credit_value(credits, TRANSLATOR_LABEL_PATTERN),
        director: director,
        genre: parse_genre(credits),
        premiere_date: parse_premiere_date(credits),
        runtime: meta[:runtime],
        runtime_minutes: parse_runtime_minutes(meta[:runtime]),
        age_rating: meta[:age_rating],
        cast_members: parse_cast_members(doc),
        creative_team: parse_creative_team(credits),
        description: parse_description(doc),
        poster_url: extract_poster_url(doc),
        is_guest: guest_production?(title, organizer),
        status: "active"
      }
    end

    private

    def collect_detail_urls
      repertuaras_urls = collect_repertuaras_urls
      if repertuaras_urls.any?
        @enumeration_source = :repertuaras
        return repertuaras_urls.sort
      end

      Rails.logger.warn(
        "[KlaipedosCatalogScraper] /repertuaras/ returned 0 URLs — falling back to events sitemap"
      )
      @enumeration_source = :sitemap_fallback
      collect_sitemap_urls.sort
    end

    def collect_sitemap_urls
      urls = Set.new

      SITEMAP_URLS.each do |sitemap_url|
        sleep DELAY_BETWEEN_REQUESTS
        body = @http.get(sitemap_url).body
        body.scan(%r{https://kdt\.lt/renginiai/[^<\s]+}).each do |raw_url|
          normalized = normalize_detail_url(raw_url)
          urls << normalized if normalized.match?(TOP_LEVEL_RENGINIAI_URL)
        end
      end

      urls.to_a
    end

    def collect_repertuaras_urls
      doc = html_doc(REPERTUARAS_URL)
      doc.css("a[href*='/renginiai/']").filter_map do |link|
        normalize_detail_url(link["href"])
      end.uniq
    end

    def report_recon(detail_urls)
      @recon_reported = true
      repertuaras_count = collect_repertuaras_urls.size
      source_label = @enumeration_source == :sitemap_fallback ? "events sitemap (fallback)" : "/repertuaras/"

      puts "\n=== KlaipedosCatalogScraper RECON ==="
      puts "Catalog enumeration source: #{source_label}"
      puts "Unique /renginiai/ links on /repertuaras/: #{repertuaras_count}"
      puts "Production URLs to scrape: #{detail_urls.size}"
      if @enumeration_source == :sitemap_fallback
        puts "Sitemap fallback: events-sitemap.xml + events-sitemap2.xml (top-level /renginiai/{slug}/ only)"
      end
      puts "Selectors:"
      puts "  poster: meta[property='og:image'] when /fliko-api/, else first content img with /fliko-api/"
      puts "  title: h1 (strip leading PREMJERA.)"
      puts "  category filter: .grid.grid-cols-12.bg-white text (#spektakliai keep, #Kiti renginiai skip)"
      puts "  credits: .tribe-events-single-event-description p / .tribe-events-content p (LABEL + strong)"
      puts "  screenings: .show-list .show-item + .others-show-list .show-item"
      puts "    hall: .show-title | date/time: .date | ticket: a[href*='bilietai.kdt.lt/kasa/seansas/']"
      puts "  runtime/age: .grid.grid-cols-12.bg-white text (e.g. 'V 2 val. 30 min.')"
      puts "  organizer: 'Organizatorius:' in .grid.grid-cols-12.bg-white"
      puts ""
    end

    def theatre_production?(doc)
      sidebar_text = doc.at_css(".grid.grid-cols-12.bg-white")&.text.to_s
      return false if sidebar_text.match?(OTHER_EVENT_TAG_PATTERN)

      credits = parse_credit_paragraphs(doc)
      return true if sidebar_text.match?(SPEKTAKLIAI_TAG_PATTERN)
      return true if resolve_director(credits).present?

      credits.any? { |c| c[:label].to_s.match?(CAST_LABEL_PATTERN) || c[:label].to_s.match?(AUTHOR_LABEL_PATTERN) }
    end

    def guest_production?(title, organizer)
      title.to_s.match?(GUEST_COUNTRY_IN_TITLE_PATTERN) ||
        (organizer.present? && !organizer.match?(KDT_ORGANIZER_PATTERN))
    end

    def parse_credit_paragraphs(doc)
      doc.css(".tribe-events-single-event-description p, .tribe-events-content p").filter_map do |paragraph|
        parse_credit_paragraph(paragraph)
      end
    end

    def parse_credit_paragraph(paragraph)
      strong_text = clean_text(paragraph.at_css("strong")&.text)
      full_text = strip_bom(clean_text(paragraph.text))
      return nil if full_text.blank?

      if strong_text.present? && full_text.start_with?(strong_text)
        remainder = strip_bom(clean_text(full_text.sub(strong_text, "")))
        label = strong_text.sub(/:\z/, "")

        if remainder.present? && inline_role_label?(label)
          { label: label, value: remainder, raw: full_text, type: :label_value }
        else
          { label: label, value: nil, raw: full_text, type: :heading }
        end
      elsif strong_text.present?
        label = strip_bom(clean_text(full_text.sub(strong_text, ""))).sub(/:\z/, "").presence || full_text
        { label: label, value: strong_text, raw: full_text, type: :label_value }
      else
        label, value = full_text.split(/:\s*/, 2)
        if value.present?
          { label: label, value: value, raw: full_text, type: :colon }
        elsif (inline = split_inline_role_line(full_text))
          inline.merge(raw: full_text, type: :label_value)
        else
          { label: full_text, value: nil, raw: full_text, type: :text }
        end
      end
    end

    def inline_role_label?(label)
      label.match?(DIRECTOR_LABEL_PATTERN) ||
        label.match?(AUTHOR_LABEL_PATTERN) ||
        label.match?(TRANSLATOR_LABEL_PATTERN) ||
        CREW_LABEL_MAPPINGS.any? { |m| label.match?(m[:pattern]) }
    end

    def split_inline_role_line(text)
      match = text.match(/\A(#{inline_role_prefixes})\s+(.+)\z/i)
      return nil unless match

      { label: match[1], value: match[2] }
    end

    def inline_role_prefixes
      @inline_role_prefixes ||= begin
        prefixes = [
          "Pjesės autorius", "Režisierius", "Režisierė", "Dramaturgas", "Scenografas", "Scenografė",
          "Kompozitorius", "Kompozitorė", "Choreografas", "Choreografė", "Garso režisierius",
          "Kostiumų dailininkė", "Kostiumų dailininkas", "Vaizdo menininkas", "Šviesų dailininkas",
          "Iš prancūzų kalbos vertė", "Iš švedų kalbos vertė"
        ]
        Regexp.union(prefixes.sort_by { |p| -p.length })
      end
    end

    def credit_value(credits, label_pattern, prefer: nil)
      matches = credits.select { |c| c[:label].to_s.match?(label_pattern) && c[:value].present? }
      row = prefer ? matches.find { |c| c[:label].to_s.match?(prefer) } : nil
      row ||= matches.first
      clean_text(row[:value]) if row
    end

    def resolve_director(credits)
      credits.each do |row|
        label = row[:label].to_s
        next unless label.match?(DIRECTOR_LABEL_PATTERN)
        next if label.match?(DIRECTOR_EXCLUDE_PATTERN)

        value = row[:value].presence
        if value.present?
          return clean_text(value)
        end

        if row[:type] == :colon
          return clean_text(row[:value])
        end
      end

      nil
    end

    def parse_genre(credits)
      credits.each do |row|
        label = row[:label].to_s
        text = strip_bom(row[:raw].to_s)
        next if label.match?(DIRECTOR_LABEL_PATTERN) || label.match?(AUTHOR_LABEL_PATTERN)
        next if CREW_LABEL_MAPPINGS.any? { |m| label.match?(m[:pattern]) }

        next unless text.match?(GENRE_LINE_PATTERN) ||
                    text.match?(/\A(?:KOMEDIJA|DRAMA|MUSICALAS|TRAGEDIJA)\b/i)

        return strip_bom(clean_text(row[:value] || row[:label] || text))
      end

      nil
    end

    def parse_premiere_date(credits)
      credits.each do |row|
        text = row[:raw].to_s
        next unless text.match?(PREMIERE_LABEL_PATTERN)

        match = text.match(/(\d{4})\s+(\d{1,2})\s+(\d{1,2})/)
        next unless match

        return Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
      end

      nil
    end

    def content_paragraph_nodes(doc)
      doc.css(".tribe-events-single-event-description p, .tribe-events-content p")
    end

    def description_prose_paragraph?(paragraph)
      return false if paragraph.at_css("strong")

      clean_text(paragraph.text).length >= 60
    end

    def parse_cast_members(doc)
      cast_block = extract_cast_block_paragraphs(doc)
      return [] if cast_block.empty?

      cast_block.flat_map { |paragraph| cast_actors_from_paragraph(paragraph) }
                .map { |name| clean_text(name) }
                .reject(&:blank?)
                .uniq
    end

    def extract_cast_block_paragraphs(doc)
      block = []
      in_cast = false

      content_paragraph_nodes(doc).each do |paragraph|
        break if in_cast && description_prose_paragraph?(paragraph)

        text = clean_text(paragraph.text)
        if cast_marker_paragraph?(text)
          in_cast = true
          block << paragraph if cast_marker_inline_content?(text)
          next
        end

        block << paragraph if in_cast
      end

      block
    end

    def cast_marker_paragraph?(text)
      text.match?(CAST_MARKER_LINE)
    end

    def cast_marker_inline_content?(text)
      cast_marker_paragraph?(text) && strip_cast_marker_prefix(text).present?
    end

    def strip_cast_marker_prefix(text)
      clean_text(text).sub(CAST_MARKER_LINE, "").strip
    end

    def cast_actors_from_paragraph(paragraph)
      text = clean_text(paragraph.text)
      return [] if text.blank?

      strong_text = cast_line_strong_text(paragraph)

      # Format 1: spaced dash — actor is always in <strong>, split alternates on "/".
      if text.match?(ROLE_ACTOR_SEPARATOR)
        return split_slash_actors(strong_text)
      end

      remainder = cast_line_actor_remainder(paragraph)

      # Format 2: <strong>ROLE</strong> plain ACTOR — actor is the plain remainder.
      if remainder.present?
        return split_comma_actors(remainder)
      end

      # Format 3: entirely bold — actor list lives in <strong>, split on "," (and "/" alternates).
      if cast_line_entirely_bold?(paragraph) && strong_text.present?
        return split_cast_list_actors(strong_text)
      end

      strong_text.present? ? split_cast_list_actors(strong_text) : []
    end

    def cast_line_strong_text(paragraph)
      strip_cast_marker_prefix(paragraph.css("strong").map(&:text).join(" "))
    end

    def cast_line_entirely_bold?(paragraph)
      text = clean_text(paragraph.text)
      strong_text = clean_text(paragraph.css("strong").map(&:text).join)
      strong_text.present? && strong_text == text
    end

    def cast_line_actor_remainder(paragraph)
      fragment = paragraph.dup
      fragment.css("strong").remove
      clean_text(fragment.text)
    end

    def split_slash_actors(text)
      clean_text(text).split(/\s*\/\s*/).map(&:strip).reject(&:blank?)
    end

    def split_comma_actors(text)
      clean_text(text).split(/,/).map(&:strip).reject(&:blank?)
    end

    def split_cast_list_actors(text)
      clean_text(text).split(/[,\/]/).map(&:strip).reject(&:blank?)
    end

    def parse_creative_team(credits)
      team = {}

      credits.each do |row|
        label = row[:label].to_s
        value = row[:value].to_s
        next if value.blank?
        next if label.match?(CAST_LABEL_PATTERN)

        CREW_LABEL_MAPPINGS.each do |mapping|
          next unless label.match?(mapping[:pattern])

          mapping[:keys].each do |key|
            team[key.to_s] = value
          end
        end
      end

      team.presence
    end

    def parse_description(doc)
      content_paragraph_nodes(doc)
        .select { |paragraph| description_prose_paragraph?(paragraph) }
        .map { |paragraph| clean_text(paragraph.text) }
        .join("\n\n")
        .presence
    end

    def parse_show_meta(doc)
      text = doc.at_css(".grid.grid-cols-12.bg-white")&.text.to_s

      age_rating = text[/\b(N-\d+|V)\b/, 1]
      runtime = text[/(\d+\s*val\.?\s*(?:\d+\s*min\.?)?)/i, 1]

      { age_rating: age_rating, runtime: runtime }
    end

    def parse_organizer(doc)
      text = doc.at_css(".grid.grid-cols-12.bg-white")&.text.to_s
      match = text.match(/Organizatorius:\s*([^\n#]+)/i)
      clean_text(match[1]) if match
    end

    def extract_poster_url(doc)
      og_image = doc.at_css('meta[property="og:image"]')&.[]("content")
      return absolute_url(og_image) if og_image.present? && og_image.match?(FLIKO_POSTER_PATTERN)

      content_img = doc.css(CONTENT_POSTER_IMG_SELECTOR).find do |img|
        img["src"].to_s.match?(FLIKO_POSTER_PATTERN)
      end

      src = content_img&.[]("src")
      absolute_url(src) if src.present?
    end

    def clean_title(text)
      clean_text(text).sub(/\APREMJERA\.?\s+/i, "")
    end

    def parse_runtime_minutes(runtime)
      return nil if runtime.blank?

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
      "#{BASE_URL}/renginiai/#{normalize_slug(slug)}/"
    end

    def slug_from_url(url)
      path = url.to_s
      path = URI.parse(path).path if path.start_with?("http")
      segments = path.split("/").reject(&:blank?)
      segments.last
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
      URI.join(BASE_URL + "/", escaped_href).to_s
    end

    def clean_text(text)
      strip_bom(text.to_s.gsub(/\u00A0/, " ")).squish
    end

    def strip_bom(text)
      text.to_s.delete("\uFEFF")
    end

    def normalize_venue(name)
      key = clean_text(name).downcase
      VENUE_ALIASES.fetch(key, clean_text(name))
    end
  end
end
