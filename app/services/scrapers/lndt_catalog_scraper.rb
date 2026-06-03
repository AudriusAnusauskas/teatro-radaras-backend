require "nokogiri"
require "faraday/retry"
require "set"

module Scrapers
  class LndtCatalogScraper
    BASE_URL = "https://www.teatras.lt"
    LIST_URL = "https://www.teatras.lt/lt/spektakliai/repertuariniai-lndt-spektakliai/"
    PAGE_SIZE = 20
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt)"
    DELAY_BETWEEN_REQUESTS = 1.5 # seconds

    MONTHS = {
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
      "gruodžio" => 12,
      "sausis" => 1,
      "vasaris" => 2,
      "kovas" => 3,
      "balandis" => 4,
      "gegužė" => 5,
      "birželis" => 6,
      "liepa" => 7,
      "rugpjūtis" => 8,
      "rugsėjis" => 9,
      "spalis" => 10,
      "lapkritis" => 11,
      "gruodis" => 12
    }.freeze

    CREATIVE_TEAM_KEYS = {
      "dailinink" => :scenographer,
      "scenograf" => :scenographer,
      "kostium" => :costume_designer,
      "kompozitor" => :composer,
      "švies" => :lighting_designer,
      "svies" => :lighting_designer,
      "choreograf" => :choreographer,
      "judes" => :movement_coordinator,
      "prodiuser" => :producer,
      "dramaturg" => :dramaturg
    }.freeze

    # Titles containing these keywords are events (talks, discussions, etc.),
    # not repertoire productions, and must not be imported.
    NON_PRODUCTION_KEYWORDS = %w[pokalbiai diskusija pristatymas susitikimas workshopas].freeze

    def initialize(http: nil)
      @http = http || Faraday.new(url: BASE_URL) do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
    end

    # Returns array of {slug, url, title} hashes from all paginated catalog pages.
    def fetch_catalog_list
      productions = []
      seen_slugs = Set.new
      offset = 0

      loop do
        url = catalog_page_url(offset)
        page_items = fetch_list_page(url)
        break if page_items.empty?

        new_items = page_items.reject { |item| seen_slugs.include?(item[:slug]) }
        break if new_items.empty?

        productions.concat(new_items)
        new_items.each { |item| seen_slugs.add(item[:slug]) }
        offset += PAGE_SIZE
        sleep 1
      end

      productions
    end

    # Returns full production hash for one detail URL.
    def fetch_production_detail(url)
      Rails.logger.info("[LndtCatalogScraper] Fetching detail from #{url}")
      doc = html_doc(path_for(url))
      meta = performance_meta(doc, url)
      director = director_from_meta(doc, meta, url)
      title = extract_title(doc, url)

      {
        source_url: canonical_url(url),
        slug: slug_from_url(url),
        title: title,
        full_title: title,
        author: author_from_title(title),
        director_name: director[:name],
        director_url: director[:url],
        genre: nil,
        premiere_date: parse_premiere_date(meta["Premjeros data"]),
        runtime: meta["Trukmė"],
        runtime_minutes: parse_runtime_minutes(meta["Trukmė"]),
        age_rating: extract_age_rating(meta),
        description: extract_description(doc, url),
        poster_url: extract_poster_url(doc, url),
        cast: parse_cast(doc),
        creative_team: parse_creators(doc),
        upcoming_showings: parse_showings(doc)
      }
    end

    # Combines catalog pagination + detail fetches with a polite delay.
    def fetch_all
      fetch_catalog_list.filter_map.with_index do |item, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        detail = fetch_production_detail(item[:url])

        if event_title?(detail[:title])
          Rails.logger.warn("[LndtCatalogScraper] Skipping non-production (event) page: #{detail[:title].inspect} (#{item[:url]})")
          next
        end

        detail
      end
    end

    private

    def event_title?(title)
      return false if title.blank?

      downcased = title.downcase
      NON_PRODUCTION_KEYWORDS.any? { |kw| downcased.include?(kw) }
    end

    def fetch_list_page(url)
      Rails.logger.info("[LndtCatalogScraper] Fetching catalog page from #{url}")
      doc = html_doc(path_for(url))
      items = doc.css('a[href*="/lt/spektakliai/"]').filter_map do |link|
        url = absolute_url(link["href"])
        next unless production_detail_url?(url)

        title = clean_text(link.text)
        next if title.blank?

        { slug: slug_from_url(url), url: url, title: title }
      end.uniq { |item| item[:slug] }

      Rails.logger.info("[LndtCatalogScraper] Found #{items.size} catalog items on #{url}")
      items
    end

    def catalog_page_url(offset)
      offset.zero? ? LIST_URL : "#{LIST_URL},offset.#{offset}"
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
      URI.parse(url).path.match?(%r{\A/lt/spektakliai/[^/]+/?\z}) &&
        !url.match?(%r{/lt/spektakliai/(repertuariniai-lndt-spektakliai|verciami-spektakliai|paskutini-karta-rodomi-spektakliai)/?\z})
    end

    def slug_from_url(url)
      URI.parse(url).path.split("/").reject(&:blank?).last
    end

    def extract_title(doc, url)
      title = clean_text(doc.at_css(".detailed-performance h1")&.text)
      warn_missing("title", url) if title.blank?
      title.presence
    end

    def performance_meta(doc, _url)
      doc.css("ul.performance-about li").each_with_object({}) do |li, meta|
        label = clean_text(li.at_css("span")&.text)
        value = clean_text(li.at_css("p")&.text)

        if label.blank? && value.match?(/\AN-\d+/i)
          meta["Age"] = value
        elsif label.present?
          meta[label] = value
        end
      end
    end

    def director_from_meta(doc, meta, url)
      link = doc.css("ul.performance-about li").find { |li| clean_text(li.at_css("span")&.text).match?(/Režis/i) }&.at_css("a")
      name = clean_text(link&.text).presence || meta["Režisūra"].presence
      warn_missing("director", url) if name.blank?

      {
        name: name,
        url: link ? absolute_url(link["href"]) : nil
      }
    end

    def extract_age_rating(meta)
      value = meta["Age"]
      value&.match(/\AN-\d+/i)&.[](0)
    end

    def extract_description(doc, url)
      node = doc.at_css(".performance-dates .content-wrapper .expander") || doc.at_css(".content-wrapper .expander")
      warn_missing("description", url) unless node

      clean_text(node&.text).presence
    end

    def extract_poster_url(doc, url)
      src = doc.at_css(".detailed-performance .new-top-info + .col img")&.[]("src") ||
            doc.at_css(".detailed-performance > .section img")&.[]("src")
      warn_missing("poster_url", url) if src.blank?

      src ? absolute_url(src) : nil
    end

    def author_from_title(title)
      return nil if title.blank?

      parts = title.split(".").map(&:strip)
      return nil if parts.size < 2

      parts.first.presence
    end

    def parse_creators(doc)
      creator_items(doc).each_with_object({}) do |li, team|
        role, value = split_role_value(li)
        key = creative_team_key(role)
        next unless key && value.present?

        team[key] = value
      end
    end

    def creator_items(doc)
      creators_heading = doc.css(".performance-creators h2").find { |h| clean_text(h.text) == "Kūrėjai" }
      container = creators_heading&.next_element
      container&.css("li") || []
    end

    def split_role_value(li)
      role = clean_text(li.at_css("strong")&.text)
      value = clean_text(li.text.sub(li.at_css("strong")&.text.to_s, "").sub(/\A\s*[—-]\s*/, ""))
      [role, value]
    end

    def creative_team_key(role)
      normalized_role = normalize_lithuanian(role.to_s.downcase)
      CREATIVE_TEAM_KEYS.find { |needle, _key| normalized_role.include?(needle) }&.last
    end

    def parse_cast(doc)
      cast_heading = doc.css(".performance-creators h3").find { |h| clean_text(h.text) == "Vaidina" }
      cast_heading&.next_element&.css("li")&.map { |li| clean_text(li.text) }&.compact_blank || []
    end

    def parse_showings(doc)
      doc.css("ul.performance-dates li").filter_map do |li|
        date_text = clean_text(li.at_css(".item-date-wr strong")&.text)
        starts_at = parse_showing_datetime(date_text)

        {
          starts_at: starts_at,
          venue: clean_text(li.at_css(".hall-field")&.text).presence,
          city: "Vilnius"
        }
      end
    end

    def parse_premiere_date(text)
      return nil if text.blank?

      match = text.match(/(?<year>\d{4})\s*m\.\s*(?<month>[[:alpha:]ąčęėįšųūž]+)\s*(?<day>\d{1,2})\s*d\./i)
      return nil unless match

      month = MONTHS[match[:month].downcase]
      return nil unless month

      Date.new(match[:year].to_i, month, match[:day].to_i).iso8601
    rescue Date::Error
      nil
    end

    def parse_showing_datetime(text)
      return nil if text.blank?

      match = text.match(/(?<month>[[:alpha:]ąčęėįšųūž]+)\s+(?<day>\d{1,2}).*?,\s*(?<hour>\d{1,2}):(?<minute>\d{2})/i)
      return nil unless match

      month = MONTHS[match[:month].downcase]
      return nil unless month

      date = next_occurrence(month, match[:day].to_i)
      Time.zone.local(date.year, date.month, date.day, match[:hour].to_i, match[:minute].to_i).iso8601
    rescue Date::Error
      nil
    end

    def next_occurrence(month, day)
      today = Time.zone.today
      date = Date.new(today.year, month, day)
      date < today ? Date.new(today.year + 1, month, day) : date
    end

    def parse_runtime_minutes(runtime)
      return nil if runtime.blank?

      hours = runtime[/(\d+)\s*val/i, 1].to_i
      minutes = runtime[/(\d+)\s*min/i, 1].to_i
      total = (hours * 60) + minutes
      total.positive? ? total : nil
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end

    def normalize_lithuanian(text)
      text.tr("ąčęėįšųūž", "aceeisuuz")
    end

    def warn_missing(field, url)
      Rails.logger.warn("[LndtCatalogScraper] Missing field '#{field}' for #{url}")
    end
  end
end
