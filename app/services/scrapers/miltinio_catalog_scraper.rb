require "nokogiri"
require "faraday/retry"

module Scrapers
  class MiltinioCatalogScraper
    BASE_URL = "https://www.miltinioteatras.lt"
    VISI_LISTING_URL = "#{BASE_URL}/spektakliai/spektakliai/visi/"
    GUEST_LISTING_URL = "#{BASE_URL}/spektakliai/spektakliai/teatro-sveciai/"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 0.3

    DIRECTOR_OVERRIDES = {
      "kunai" => { director: "Marius Pinigis", co_director: "Adrian Carlo Bibiano" }
    }.freeze

    LITHUANIAN_MONTHS = {
      "sausio" => 1, "vasario" => 2, "kovo" => 3, "balandžio" => 4,
      "gegužės" => 5, "birželio" => 6, "liepos" => 7, "rugpjūčio" => 8,
      "rugsėjo" => 9, "spalio" => 10, "lapkričio" => 11, "gruodžio" => 12
    }.freeze

    GENRE_PATTERN = /\A(?:Vienos|Dviejų).+\b(?:drama|tragedija|komedija|spektaklis)/i
    TRANSLATOR_PATTERN = /kalbos vertė/i
    DIRECTOR_PATTERN = /režisier/i
    DIRECTOR_EXCLUDE_PATTERN = /asistent|padėjėj/i
    CO_DIRECTOR_SPLIT_PATTERN = /,|\s+ir\s+/i
    CAST_HEADER_PATTERN = /\AVaidina:?\z/i
    RUNTIME_PATTERN = /Trukmė\s*[–-]/i
    PREMIERE_PATTERN = /Premjera\s*[–-]/i
    AGE_RECOMMENDATION_PATTERN = /Rekomenduojama asmenims nuo (\d+) metų/i
    AGE_RATING_PATTERN = /\A[Nn][–-]\d+\z/
    KNOWN_VENUES = ["Didžioji salė", "Mažoji salė", "Laboratorija"].freeze

    CREW_LABEL_MAPPINGS = [
      { pattern: /Šviesų dailininkas/i, keys: [:lightingDesigner] },
      { pattern: /Scenografijos/i, keys: [:scenographer] },
      { pattern: /Kostiumų/i, keys: [:costumeDesigner] },
      { pattern: /Kompozitorius/i, keys: [:composer] },
      { pattern: /Choreograf/i, keys: [:choreographer] },
      { pattern: /Vaizdo projekcijų autorius/i, keys: [:videoDesigner] },
      { pattern: /Dramaturg/i, keys: [:dramaturg] }
    ].freeze

    METADATA_LINE_PATTERN = Regexp.union(
      GENRE_PATTERN, TRANSLATOR_PATTERN, DIRECTOR_PATTERN, CAST_HEADER_PATTERN,
      RUNTIME_PATTERN, PREMIERE_PATTERN, AGE_RECOMMENDATION_PATTERN, AGE_RATING_PATTERN,
      /kalbos vertė/i, /finansuoja/i, /Rekomenduojame/i, /Spektaklyje naudojamos/i,
      *CREW_LABEL_MAPPINGS.map { |m| m[:pattern] }
    )

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

      Rails.logger.info("[MiltinioCatalogScraper] Fetching #{detail_urls.size} production detail pages")

      detail_urls.filter_map.with_index do |url, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        fetch_production_detail(url)
      rescue StandardError => e
        Rails.logger.error("[MiltinioCatalogScraper] Failed #{url}: #{e.message}")
        nil
      end
    end

    def fetch_production_detail(url)
      source_url = normalize_detail_url(url)
      slug = slug_from_url(source_url)
      is_guest = guest_url?(source_url)
      doc = html_doc(source_url)

      title = clean_text(doc.at_css("h1")&.text)
      lines = metadata_lines(doc)
      director, director_team = parse_director_info(lines)
      creative_team = merge_creative_team(parse_creative_team(lines), director_team)
      director, creative_team = apply_director_override(slug, director, creative_team || {})

      if director.blank?
        Rails.logger.warn("[MiltinioCatalogScraper] SKIP (no director): #{slug}")
        return nil
      end

      author = parse_author(lines, title)
      meta = parse_meta_fields(lines)

      {
        source_url: source_url,
        slug: slug,
        title: title,
        author: author,
        translator: parse_translator(lines),
        genre: parse_genre(lines),
        director: director,
        creative_team: creative_team.presence,
        cast_members: parse_cast_members(lines),
        runtime: meta[:runtime],
        runtime_minutes: parse_runtime_minutes(meta[:runtime]),
        premiere_date: meta[:premiere_date],
        venue: meta[:venue],
        age_rating: meta[:age_rating],
        age_note: meta[:age_note],
        poster_url: extract_poster_url(doc),
        description: parse_description(doc, lines),
        is_guest: is_guest,
        status: "active"
      }
    end

    private

    def collect_detail_urls
      visi = collect_listing_urls(VISI_LISTING_URL, "visi")
      guests = collect_listing_urls(GUEST_LISTING_URL, "teatro-sveciai")
      (visi + guests).uniq.sort
    end

    def collect_listing_urls(listing_url, section)
      doc = html_doc(listing_url)
      doc.css("a[href*='/spektaklis/spektakliai/#{section}/']").filter_map do |link|
        normalize_detail_url(link["href"])
      end.uniq
    end

    def report_recon(detail_urls)
      @recon_reported = true
      visi_count = collect_listing_urls(VISI_LISTING_URL, "visi").size
      guest_count = collect_listing_urls(GUEST_LISTING_URL, "teatro-sveciai").size

      puts "\n=== MiltinioCatalogScraper RECON ==="
      puts "Visi listing: #{VISI_LISTING_URL} → #{visi_count} detail links"
      puts "Guest listing: #{GUEST_LISTING_URL} → #{guest_count} detail links"
      puts "Combined enumeration: #{detail_urls.size}"
      puts "Selectors:"
      puts "  metadata block: div.descr (first block with Režisier/Trukmė)"
      puts "  lines: p inside div.descr (split on <br> for cast)"
      puts "  title: h1"
      puts "  author: first p line above title duplicate"
      puts "  director: p matching /Režisier/i (exclude asistent)"
      puts "  cast: after 'Vaidina:' → ROLE – ACTOR (flip to ACTOR – ROLE)"
      puts "  runtime/premiere/venue/age: labeled lines (Trukmė –, Premjera –, hall line, N–N)"
      puts "  screenings: a[href*='kakava.lt'] text '{month} {day} {Weekday} HH:MM'"
      puts "  poster: meta[property='og:image']"
      puts ""
    end

    def metadata_block(doc)
      doc.css("div.descr").find { |block| block.text.match?(/Režisier|Trukmė/i) }
    end

    def metadata_lines(doc)
      block = metadata_block(doc)
      return [] unless block

      block.css("p").flat_map { |paragraph| split_paragraph_lines(paragraph) }.map { |line| clean_text(line) }
                          .reject(&:blank?)
    end

    def split_paragraph_lines(paragraph)
      fragments = paragraph.inner_html.to_s.split(/<br\s*\/?>/i)
      lines = fragments.map { |frag| Nokogiri::HTML.fragment(frag).text.squish }.reject(&:blank?)
      return lines if lines.many?

      text = paragraph.text.squish
      return [] if text.blank?

      # Combined runtime + premiere in one paragraph.
      if text.match?(RUNTIME_PATTERN) && text.match?(PREMIERE_PATTERN)
        return text.split(/(?=Premjera\s*[–-])/i).map(&:squish).reject(&:blank?)
      end

      [text]
    end

    def parse_author(lines, title)
      return nil if lines.size < 2

      first = lines.first
      return nil if first.match?(GENRE_PATTERN)
      return nil if first.match?(DIRECTOR_PATTERN)
      return nil if normalize_compare(first) == normalize_compare(title)

      first
    end

    def parse_genre(lines)
      lines.find { |line| line.match?(GENRE_PATTERN) }
    end

    def parse_translator(lines)
      line = lines.find { |l| l.match?(TRANSLATOR_PATTERN) }
      return nil unless line

      extract_value_after_dash(line) || line.sub(/.*vertė\s*/i, "").strip.presence
    end

    def parse_director_info(lines)
      line = lines.find do |l|
        l.match?(DIRECTOR_PATTERN) && !l.match?(DIRECTOR_EXCLUDE_PATTERN)
      end
      raw = extract_value_after_dash(line) if line
      return [nil, {}] if raw.blank?

      names = split_co_directors(raw).map { |name| title_case_director_name(name) }
      director = names.first
      team = {}
      team["coDirector"] = names[1..].join(", ") if names.size > 1

      [director, team]
    end

    def split_co_directors(value)
      clean_text(value).split(CO_DIRECTOR_SPLIT_PATTERN).map(&:strip).reject(&:blank?)
    end

    def title_case_director_name(name)
      clean_text(name).split(/\s+/).map do |word|
        word.split("-").map(&:capitalize).join("-")
      end.join(" ")
    end

    def merge_creative_team(base_team, extra_team)
      (base_team || {}).merge(extra_team.compact).presence
    end

    def apply_director_override(slug, director, creative_team)
      return [director, creative_team] if director.present?

      override = DIRECTOR_OVERRIDES[slug]
      return [director, creative_team] unless override

      team = creative_team.dup
      if override[:co_director].present? && team["coDirector"].blank?
        team["coDirector"] = override[:co_director]
      end

      [override[:director], team]
    end

    def parse_creative_team(lines)
      team = {}

      lines.each do |line|
        next if line.match?(DIRECTOR_EXCLUDE_PATTERN)

        CREW_LABEL_MAPPINGS.each do |mapping|
          next unless line.match?(mapping[:pattern])

          value = extract_value_after_dash(line)
          next if value.blank?

          mapping[:keys].each { |key| team[key.to_s] = value }
        end
      end

      team.presence
    end

    def parse_cast_members(lines)
      cast = []
      in_cast = false

      lines.each do |line|
        if line.match?(CAST_HEADER_PATTERN)
          in_cast = true
          next
        end

        next unless in_cast
        break if metadata_field_line?(line)

        if (match = line.match(/\A(.+?)\s*[–-]\s*(.+)\z/))
          role = clean_text(match[1])
          actor = clean_text(match[2])
          cast << "#{actor} – #{role}"
        elsif person_name_line?(line)
          cast << line
        end
      end

      cast.uniq
    end

    def parse_meta_fields(lines)
      runtime = nil
      premiere_date = nil
      venue = nil
      age_rating = nil
      age_note = nil
      past_runtime = false

      lines.each do |line|
        if line.match?(RUNTIME_PATTERN)
          runtime = line.sub(/.*Trukmė\s*[–-]\s*/i, "").strip.presence
          past_runtime = true
          next
        end

        if line.match?(PREMIERE_PATTERN)
          premiere_date = parse_premiere_date(line)
          past_runtime = true
          next
        end

        if past_runtime && venue.blank? && venue_line?(line)
          venue = line
          next
        end

        if (match = line.match(AGE_RECOMMENDATION_PATTERN))
          age_rating = "N-#{match[1]}"
          next
        end

        if line.match?(AGE_RATING_PATTERN)
          age_rating = line.upcase.tr("-", "-")
          next
        end

        if past_runtime && age_note.blank? && line.length > 30 && line.match?(/švies|ginkl|smurt|šiltai/i)
          age_note = line
        end
      end

      { runtime: runtime, premiere_date: premiere_date, venue: venue, age_rating: age_rating, age_note: age_note }
    end

    def parse_premiere_date(line)
      match = line.match(/(\d{4})\s*m\.\s*(\p{L}+)\s+(\d{1,2})\s*d\./u)
      return nil unless match

      month = LITHUANIAN_MONTHS[match[2].downcase]
      return nil unless month

      Date.new(match[1].to_i, month, match[3].to_i)
    rescue Date::Error, ArgumentError
      nil
    end

    def parse_description(doc, _lines)
      doc.css("div.small-block p, main .small-block p").map { |p| clean_text(p.text) }
         .reject(&:blank?)
         .reject { |line| metadata_or_skip_line?(line) }
         .reject { |line| line.match?(/slapuk|cookies|reCAPTCHA|Sutinku/i) }
         .join("\n\n")
         .presence
    end

    def metadata_or_skip_line?(line)
      return true if line.match?(METADATA_LINE_PATTERN)
      return true if line.match?(CAST_HEADER_PATTERN)
      return true if cast_role_line?(line)
      return true if venue_line?(line) && KNOWN_VENUES.any? { |v| line.include?(v) }
      return true if line.match?(/Projektą finansuoja/i)

      false
    end

    def cast_role_line?(line)
      line.match?(/\A\S.+[–-]\s*\p{Lu}/u)
    end

    def metadata_field_line?(line)
      line.match?(RUNTIME_PATTERN) || line.match?(PREMIERE_PATTERN) || line.match?(AGE_RECOMMENDATION_PATTERN) ||
        line.match?(AGE_RATING_PATTERN) || venue_line?(line)
    end

    def venue_line?(line)
      return true if KNOWN_VENUES.any? { |venue| line.include?(venue) }

      line.match?(/depas|teatras|salė/i) && line.length < 120
    end

    def person_name_line?(line)
      line.match?(/\A(?:Ponas|Namsargė|[^\s–-]+)\s+\p{Lu}[\p{L}]+(?:\s+\p{Lu}[\p{L}]+)+\z/u)
    end

    def extract_value_after_dash(line)
      match = line.match(/[–-]\s*(.+)\z/)
      clean_text(match[1]) if match
    end

    def parse_runtime_minutes(runtime)
      return nil if runtime.blank?

      hours = runtime[/(\d+)\s*val/i, 1].to_i
      minutes = runtime[/(\d+)\s*min/i, 1].to_i
      total = (hours * 60) + minutes
      total.positive? ? total : nil
    end

    def extract_poster_url(doc)
      og_image = doc.at_css('meta[property="og:image"]')&.[]("content")
      absolute_url(og_image) if og_image.present?
    end

    def guest_url?(url)
      url.include?("/teatro-sveciai/")
    end

    def normalize_detail_url(href)
      url = absolute_url(href)
      uri = URI.parse(url)
      segments = uri.path.split("/").reject(&:blank?)
      section_index = segments.index("spektakliai")
      section = segments[section_index + 1] if section_index
      slug = segments.last

      if section == "teatro-sveciai"
        "#{BASE_URL}/spektaklis/spektakliai/teatro-sveciai/#{slug}/"
      else
        "#{BASE_URL}/spektaklis/spektakliai/visi/#{slug}/"
      end
    end

    def slug_from_url(url)
      URI.parse(url).path.split("/").reject(&:blank?).last
    end

    def html_doc(path_or_url)
      response = @http.get(path_for(path_or_url))
      Nokogiri::HTML(response.body)
    end

    def path_for(path_or_url)
      uri = URI.parse(path_or_url)
      return path_or_url if uri.relative?

      uri.path
    end

    def absolute_url(href)
      escaped = URI::DEFAULT_PARSER.escape(href.to_s.strip)
      URI.join(BASE_URL + "/", escaped).to_s
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end

    def normalize_compare(text)
      ActiveSupport::Inflector.transliterate(text.to_s).downcase.squish
    end
  end
end
