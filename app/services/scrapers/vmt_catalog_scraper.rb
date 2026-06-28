require "nokogiri"
require "faraday/retry"
require "date"

module Scrapers
  class VmtCatalogScraper
    BASE_URL = "https://www.vmt.lt"
    LIST_URL = "https://www.vmt.lt/spektakliai"
    REPERTOIRE_URL = "https://www.vmt.lt/repertuaras"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 1.5
    SKIP_FILT = %w[4 9].freeze # Renginiai, Ekskursija

    LITHUANIAN_MONTHS = {
      "sausio" => 1,
      "vasario" => 2,
      "kovo" => 3,
      "balandžio" => 4,
      "gegužės" => 5,
      "birželio" => 6,
      "liepos" => 7,
      "rugpjūčio" => 8,
      "rugsėjo" => 9,
      "spalio" => 10,
      "lapkričio" => 11,
      "gruodžio" => 12
    }.freeze

    DIRECTOR_COMBINED_PATTERN = /(?:Autorius ir režisierius|Pjesės autorius ir režisierius)\s*[–—-]\s*(.+)/i
    # VMT director lives in the header block above "Artimiausios datos", not in "Komanda".
    DIRECTOR_HEADER_PATTERN = /Režisier[iųė][a-zų]*\s*[–—-]\s*(.+)/i
    KOMANDA_DIRECTOR_LABEL_PATTERN = /\ARežisier(?:ius|ė|iai)\z/i
    CO_DIRECTOR_IR_PATTERN = /\s+ir\s+/i
    DIRECTOR_COUNTRY_SUFFIX_PATTERN = /\s*\([^)]+\)\z/
    IDEA_AUTHOR_PATTERN = /\AIdėjos\s+autor(?:ė|ius)\s*[–—-]\s*(.+)\z/i
    PREMIERE_PATTERN = /(\d{4})\s*m\.\s*([a-ząčęėįšųūž]+)\s+(\d{1,2})\s*d\./i
    AGE_RATING_PATTERN = /\(N-?\s*(\d+)\)|\bN-?\s*(\d+)\b/i
    TRANSLATOR_LABEL_PATTERN = /vertė/i
    VENUE_FESTIVAL_SUFFIX_PATTERN = /teatre|teatras|festivaliy|festivalyje|Rokiškyje|dramos\s+teatre|kitame\s+teatre/i

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    def fetch_catalog_list
      Rails.logger.info("[VmtCatalogScraper] Collecting URLs from list + repertoire")
      collect_production_urls.map do |slug, url|
        { slug: slug, url: url }
      end
    end

    def fetch_production_detail(url)
      normalized_slug = slug_from_url(url)
      fetch_url = fetch_url_for(url)
      stored_source_url = canonical_production_url(normalized_slug)
      Rails.logger.info("[VmtCatalogScraper] Fetching detail from #{fetch_url}")
      doc = html_doc(fetch_url)
      layer = doc.at_css("div.layer .small-wrap")
      tags = extract_tags(doc)
      intro_text = clean_text(layer&.at_css("div.intro p")&.text)
      header_lines = header_metadata_lines(layer)
      author_info = parse_author_and_director(header_lines)
      runtime_text, premiere_text = parse_runtime_premiere(header_lines)
      sections = parse_heading_sections(layer)
      creative_team = sections[:creative_team].merge(author_info[:director_team])
      description = extract_description(layer)
      age_source = [intro_text, description].compact.join("\n")
      raw_title = clean_text(doc.at_css("div.performance .content h1")&.text)
      title = classify_pipe_title(raw_title)
      if title == :skip
        Rails.logger.info(
          "[VmtCatalogScraper] Skipping tour/festival entry: #{raw_title.inspect} (#{url})"
        )
        return nil
      end

      {
        title: title,
        slug: normalized_slug,
        source_url: stored_source_url,
        author: author_info[:author],
        director_name: author_info[:director_name],
        translator: extract_translator(sections[:creative_team]),
        genre: intro_text.presence,
        age_rating: extract_age_rating(age_source),
        runtime: runtime_text,
        runtime_minutes: parse_runtime_minutes(runtime_text),
        premiere_date: parse_premiere_date(premiere_text),
        description: description,
        cast: flatten_cast(sections[:cast_rows]),
        creative_team: creative_team,
        poster_url: extract_poster_url(doc),
        is_guest: tags.include?("Svečiai"),
        tags: tags
      }
    end

    def fetch_all
      urls = collect_production_urls

      urls.values.filter_map.with_index do |url, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        detail = fetch_production_detail(url)
        next unless detail

        detail
      rescue StandardError => e
        Rails.logger.error("[VmtCatalogScraper] Failed #{url}: #{e.message}")
        nil
      end
    end

    private

    def collect_production_urls
      list_slugs = slugs_from_list_page
      repertoire_slugs = slugs_from_repertoire_page

      merged = list_slugs.merge(repertoire_slugs)
      Rails.logger.info(
        "[VmtCatalogScraper] URLs: list=#{list_slugs.size}, repertoire=#{repertoire_slugs.size}, " \
        "union=#{merged.size}"
      )
      merged
    end

    def slugs_from_list_page
      doc = html_doc(LIST_URL)
      slugs = {}

      doc.css(".single-performance").each do |card|
        filt = card["data-filt"]
        next if skip_filt?(filt)

        link = card.at_css('a[href*="/spektakliai/"]')
        next unless link

        url = absolute_url(link["href"])
        next unless production_detail_url?(url)

        remember_slug(slugs, url)
      end

      slugs
    end

    def slugs_from_repertoire_page
      doc = html_doc(REPERTOIRE_URL)
      slugs = {}

      doc.css('a[href*="/spektakliai/"]').each do |link|
        url = absolute_url(link["href"])
        next unless production_detail_url?(url)

        remember_slug(slugs, url)
      end

      slugs
    end

    def remember_slug(slugs, url)
      key = slug_from_url(url)
      return if key.blank?

      slugs[key] = pick_preferred_fetch_url(slugs[key], absolute_url(url))
    end

    # Dedup key is lowercased slug; value is original-case URL for HTTP fetch.
    def pick_preferred_fetch_url(current, candidate)
      return candidate if current.nil?

      current_segment = path_slug_segment(current)
      candidate_segment = path_slug_segment(candidate)
      return candidate if current_segment.match?(/\.+\z/) && !candidate_segment.match?(/\.+\z/)
      return current if !current_segment.match?(/\.+\z/) && candidate_segment.match?(/\.+\z/)

      # VMT CMS paths are case-sensitive — prefer mixed-case over all-lowercase.
      return candidate if mixed_case_slug?(candidate_segment) && !mixed_case_slug?(current_segment)

      current
    end

    def mixed_case_slug?(segment)
      segment.present? && segment != segment.downcase
    end

    def path_slug_segment(url)
      URI.parse(url).path.split("/").reject(&:blank?).last.to_s
    end

    def fetch_url_for(url)
      absolute_url(url)
    end

    def classify_pipe_title(title)
      return title if title.blank?
      return title unless title.include?("|")

      base, suffix = title.split("|", 2).map { |part| clean_text(part) }
      return base if suffix.blank?

      suffix.match?(VENUE_FESTIVAL_SUFFIX_PATTERN) ? :skip : base
    end

    def skip_filt?(filt)
      return false if filt.blank?

      filt.split(",").map(&:strip).any? { |id| SKIP_FILT.include?(id) }
    end

    def extract_tags(doc)
      doc.css("div.performance .content .tag.yellow").filter_map do |tag|
        clean_text(tag.text).presence
      end.uniq
    end

    # Lines from intro + metadata row, stopping before "Artimiausios datos" (header block).
    def header_metadata_lines(layer)
      lines = []

      layer&.element_children&.each do |child|
        break if child.name == "h2" && clean_text(child.text) == "Artimiausios datos"

        next unless child.name == "div"
        next if child["class"].to_s.include?("row-cta")
        next unless child["class"].to_s.include?("intro") || child["class"].to_s.include?("row")

        child.css("p").each do |paragraph|
          paragraph.inner_html.split(/<br\s*\/?>/i).each do |fragment|
            line = clean_text(Nokogiri::HTML.fragment(fragment).text)
            lines << line unless line.blank?
          end
        end
      end

      lines
    end

    def parse_author_and_director(lines)
      author_lines = []
      director_name = nil
      director_team = {}
      idea_author_name = nil

      lines.each do |line|
        if (match = line.match(DIRECTOR_COMBINED_PATTERN))
          director_name, director_team = parse_header_director_value(match[1])
          author_lines << match.pre_match.strip if match.pre_match.present?
          next
        end

        if (match = line.match(DIRECTOR_HEADER_PATTERN))
          parsed_director, parsed_team = parse_header_director_value(match[1])
          director_name = parsed_director
          director_team = parsed_team
          author_lines << match.pre_match.strip if match.pre_match.present?
          next
        end

        if (match = line.match(IDEA_AUTHOR_PATTERN))
          idea_author_name ||= title_case_director_name(strip_director_suffix(match[1]))
          next
        end

        next if line.match?(/\ATrukmė\s*[–—-]/i)
        next if line.match?(/\APremjeros?\s+data\s*[–—-]|\APremjera\s*[–—-]/i)

        author_lines << line
      end

      director_name ||= idea_author_name

      {
        author: author_lines.join(" ").presence,
        director_name: director_name.presence,
        director_team: director_team
      }
    end

    def parse_runtime_premiere(lines)
      runtime_text = lines.find { |line| line.match?(/\ATrukmė\s*[–—-]/i) }
      premiere_text = lines.find { |line| line.match?(/\APremjeros?\s+data\s*[–—-]|\APremjera\s*[–—-]/i) }

      runtime_text = runtime_text&.sub(/\ATrukmė\s*[–—-]\s*/i, "")&.presence
      premiere_text = premiere_text&.sub(/\APremjeros?\s+data\s*[–—-]\s*|\APremjera\s*[–—-]\s*/i, "")&.presence

      [runtime_text, premiere_text]
    end

    # Header director value: strip country suffix, then split.
    # Comma-separated names are treated as separate production versions (ambiguous) — first only.
    # " ir " without commas means shared co-direction (e.g. Miltinio MAHAMAYA pattern).
    def parse_header_director_value(raw)
      value = clean_text(raw)
      return [nil, {}] if value.blank?

      if value.include?(",")
        director = title_case_director_name(strip_director_suffix(value.split(",").first))
        return [director, {}]
      end

      stripped = strip_director_suffix(value)
      names = stripped.split(CO_DIRECTOR_IR_PATTERN).map(&:strip).reject(&:blank?)
      director = title_case_director_name(strip_director_suffix(names.first))
      team = {}
      if names.size > 1
        team["coDirector"] = names[1..].map { |name| title_case_director_name(strip_director_suffix(name)) }.join(", ")
      end

      [director, team]
    end

    def strip_director_suffix(name)
      name.to_s.gsub(DIRECTOR_COUNTRY_SUFFIX_PATTERN, "").strip
    end

    def title_case_director_name(name)
      clean_text(name).split(/\s+/).map do |word|
        word.split("-").map(&:capitalize).join("-")
      end.join(" ")
    end

    def parse_heading_sections(layer)
      creative_team = {}
      cast_rows = []
      current_section = nil

      layer&.element_children&.each do |child|
        case child.name
        when "h2"
          heading = clean_text(child.text)
          current_section = case heading
                            when "Komanda" then :komanda
                            when "Vaidina" then :vaidina
                            else :other
                            end
        when "div"
          next unless child["class"].to_s.include?("row")
          next if child["class"].to_s.include?("row-cta")

          label, value = row_label_value(child)
          next if label.blank?

          case current_section
          when :komanda
            next if komanda_director_label?(label)

            creative_team[label] = value
          when :vaidina
            cast_rows << { role: label, actors: value }
          end
        end
      end

      { creative_team: creative_team, cast_rows: cast_rows }
    end

    def komanda_director_label?(label)
      clean_text(label).match?(KOMANDA_DIRECTOR_LABEL_PATTERN)
    end

    def row_label_value(row)
      divs = row.element_children.select { |node| node.name == "div" }
      [clean_text(divs[0]&.text), clean_text(divs[1]&.text)]
    end

    def extract_translator(creative_team)
      entry = creative_team.find { |label, _| label.match?(TRANSLATOR_LABEL_PATTERN) }
      entry&.last.presence
    end

    def flatten_cast(cast_rows)
      cast_rows.flat_map do |row|
        row[:actors].to_s.split(",").map { |name| clean_text(name) }.reject(&:blank?)
      end.uniq
    end

    def extract_description(layer)
      layer&.css("div.description")&.each do |block|
        text = clean_text(block.css("p").map(&:text).join("\n\n"))
        next if text.blank?
        next if text.match?(/\APapildoma informacija:/i)
        next if text.match?(/\ARecenzijos:/i)
        next if block.at_css("strong")&.text.to_s.include?("Papildoma informacija")
        next if block.at_css("strong")&.text.to_s.include?("Recenzijos")

        return text
      end

      nil
    end

    def extract_age_rating(text)
      match = text.to_s.match(AGE_RATING_PATTERN)
      return nil unless match

      rating = match[1] || match[2]
      "N-#{rating}"
    end

    def parse_premiere_date(text)
      return nil if text.blank?

      match = clean_text(text).match(PREMIERE_PATTERN)
      return nil unless match

      year = match[1].to_i
      month = LITHUANIAN_MONTHS[match[2].downcase]
      return nil unless month

      Date.new(year, month, match[3].to_i).iso8601
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

    def extract_poster_url(doc)
      src = doc.at_css("div.performance img")&.[]("src")
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

    def canonical_production_url(slug)
      "#{BASE_URL}/spektakliai/#{normalize_slug(slug)}"
    end

    def production_detail_url?(url)
      path = URI.parse(url).path
      path.match?(%r{\A/spektakliai/[^/]+/?\z}) && path != "/spektakliai"
    end

    def slug_from_url(url)
      normalize_slug(URI.parse(url).path.split("/").reject(&:blank?).last)
    end

    def normalize_slug(slug)
      slug.to_s.strip.sub(/\.+\z/, "").downcase
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end
  end
end
