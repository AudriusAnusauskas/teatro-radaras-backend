require "json"
require "cgi"

module Scrapers
  class DirectorWikidataEnricher
    USER_AGENT = "TeatroRadaras/1.0 (https://teatroradaras.lt; <Audrius will set contact>)"
    DELAY_BETWEEN_REQUESTS = 0.3
    WIKIDATA_API = "https://www.wikidata.org/w/api.php"
    COMMONS_API = "https://commons.wikimedia.org/w/api.php"
    COMMONS_FILE_PATH = "https://commons.wikimedia.org/wiki/Special:FilePath/"

    HUMAN_QID = "Q5"
    DIRECTOR_OCCUPATION_QIDS = %w[
      Q3387717
      Q2526255
      Q1075651
      Q3455803
    ].freeze
    DIRECTOR_DESCRIPTION_PATTERN = /director|režisier|reżyser|regista|regiseur|instruttore?|directeur/i

    BIO_MODEL = "claude-sonnet-4-5-20250929"

    BIO_PRESENT_TENSE_PATTERN = /\b(yra|kuria|dirba|derina|pastato|režisuoja|žaidžia|kurio)\b/i

    DISSOLVED_STATE_QIDS = %w[
      Q151
      Q34266
      Q2184
      Q2307919
      Q170770
      Q11772
      Q28513
    ].freeze

    NATIONALITY_ADJECTIVE_MAP = {
      "lithuanian" => "Lietuva",
      "lietuvių" => "Lietuva",
      "croatian" => "Kroatija",
      "slovenian" => "Slovėnija",
      "hungarian" => "Vengrija",
      "danish" => "Danija",
      "norwegian" => "Norvegija",
      "french" => "Prancūzija",
      "polish" => "Lenkija",
      "estonian" => "Estija",
      "german" => "Vokietija",
      "ukrainian" => "Ukraina",
      "russian" => "Rusija",
      "latvian" => "Latvija",
      "italian" => "Italija",
      "georgian" => "Sakartvelas",
      "british" => "Jungtinė Karalystė",
      "english" => "Jungtinė Karalystė",
      "american" => "JAV"
    }.freeze

    def initialize(http: nil, claude_client: nil)
      @http = http || Faraday.new do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
        f.response :raise_error
      end
      @claude_client = claude_client
    end

    # READ-ONLY: search Wikidata and print a scout table. No writes, no Claude calls.
    def scout
      rows = directors_with_blank_bio.map.with_index do |director, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        scout_director(director)
      rescue StandardError => e
        Rails.logger.error("[DirectorWikidataEnricher] Scout failed #{director.name}: #{e.message}")
        scout_row(director, error: e.message)
      end

      print_scout_table(rows)
      rows
    end

    def enrich!(dry_run: true, only_ids: nil)
      results = { enriched: 0, skipped: 0, errors: [], dry_run_rows: [] }
      scope = directors_with_blank_bio
      scope = scope.where(id: only_ids) if only_ids.present?

      scope.find_each.with_index do |director, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        process_enrichment(director, dry_run:, results:)
      rescue StandardError => e
        Rails.logger.error("[DirectorWikidataEnricher] Enrich failed #{director.name}: #{e.message}")
        results[:errors] << { id: director.id, name: director.name, error: e.message }
      end

      print_dry_run_table(results[:dry_run_rows]) if dry_run && results[:dry_run_rows].any?
      results
    end

    private

    def directors_with_blank_bio
      Director.where(bio: [nil, ""]).order(:name)
    end

    def scout_director(director)
      search_hit = search_wikidata(director.name)
      return scout_row(director, qid: "-", label: "-", description: "-", note: "no search results") unless search_hit

      entity = fetch_entity(search_hit["id"])
      return scout_row(director, qid: search_hit["id"], label: search_hit["label"], note: "entity not found") unless entity

      scout_row(
        director,
        qid: search_hit["id"],
        label: entity_label(entity) || search_hit["label"],
        description: entity_description(entity) || "-",
        is_human: human?(entity),
        occupations_count: occupation_qids(entity).size,
        has_image: image_filename(entity).present?,
        wiki: wiki_title(entity) || "-"
      )
    end

    def scout_row(director, **fields)
      {
        name: director.name,
        qid: fields[:qid] || "-",
        label: fields[:label] || "-",
        description: fields[:description] || "-",
        is_human: fields.fetch(:is_human, false),
        occupations: fields.fetch(:occupations_count, 0),
        has_image: fields.fetch(:has_image, false),
        wiki: fields[:wiki] || "-",
        note: fields[:note]
      }
    end

    def print_scout_table(rows)
      puts "\n=== Director Wikidata scout (#{rows.size} directors with blank bio) ===\n"
      header = format(
        "%-28s | %-8s | %-24s | %-32s | %-5s | %-4s | %-5s | %s",
        "Director", "QID", "Label", "Description", "Human", "P106", "Image", "Wiki"
      )
      puts header
      puts "-" * header.length

      rows.each do |row|
        if row[:note] && row[:qid] == "-"
          puts "#{row[:name].slice(0, 28).ljust(28)} | #{"-".ljust(8)} | #{"-".ljust(24)} | #{row[:note].slice(0, 32).ljust(32)} | #{"-".ljust(5)} | #{"-".ljust(4)} | #{"-".ljust(5)} | -"
          next
        end

        puts format(
          "%-28s | %-8s | %-24s | %-32s | %-5s | %-4s | %-5s | %s",
          row[:name].slice(0, 28),
          row[:qid],
          row[:label].to_s.slice(0, 24),
          row[:description].to_s.slice(0, 32),
          row[:is_human] ? "yes" : "no",
          row[:occupations].to_s,
          row[:has_image] ? "yes" : "no",
          row[:wiki].to_s.slice(0, 40)
        )
      end
      puts ""
    end

    def process_enrichment(director, dry_run:, results:)
      search_hit = search_wikidata(director.name)
      unless search_hit
        log_skip(director.name, "no Wikidata search results")
        results[:skipped] += 1
        return
      end

      entity = fetch_entity(search_hit["id"])
      unless entity
        log_skip(director.name, "entity #{search_hit["id"]} not found")
        results[:skipped] += 1
        return
      end

      unless acceptable_director_match?(entity)
        log_skip(director.name, "no confident match")
        results[:skipped] += 1
        return
      end

      proposal = build_enrichment_proposal(director, entity)
      if proposal.empty?
        log_skip(director.name, "no fields to enrich")
        results[:skipped] += 1
        return
      end

      if dry_run
        results[:dry_run_rows] << dry_run_row(director.name, proposal)
      else
        apply_enrichment!(director, proposal)
      end

      results[:enriched] += 1
    end

    def build_enrichment_proposal(director, entity)
      wiki_lang, wiki_title = preferred_wiki_sitelink(entity)
      wikipedia_source_url = nil
      extract = nil
      if wiki_title.present?
        extract = fetch_wikipedia_extract(wiki_lang, wiki_title)
        wikipedia_source_url = wikipedia_page_url(wiki_lang, wiki_title) if extract.present?
      end
      death_year = resolve_death_year(director, entity)
      bio = extract.present? ? generate_lithuanian_bio(extract, director.name, death_year:) : nil

      image_name = image_filename(entity)
      photo = image_name.present? ? commons_photo_url(image_name) : nil
      photo_credit = photo.present? && director.photo_url.blank? ? commons_photo_credit(image_name) : nil

      {
        birth_year: director.birth_year.blank? ? year_from_claim(entity, "P569") : nil,
        death_year: director.death_year.blank? ? death_year : nil,
        nationality: director.nationality.blank? ? resolve_nationality(entity) : nil,
        photo_url: director.photo_url.blank? ? photo : nil,
        photo_credit: director.photo_url.blank? ? photo_credit : nil,
        source_url: director.source_url.blank? && bio.present? ? wikipedia_source_url : nil,
        bio: director.bio.blank? ? bio : nil
      }.compact
    end

    def apply_enrichment!(director, proposal)
      director.update!(proposal)
    end

    def dry_run_row(name, proposal)
      {
        name: name,
        birth_year: proposal[:birth_year],
        death_year: proposal[:death_year],
        nationality: proposal[:nationality],
        has_photo: proposal[:photo_url].present?,
        bio_preview: proposal[:bio].to_s.slice(0, 120).presence,
        source_url: proposal[:source_url]
      }
    end

    def print_dry_run_table(rows)
      puts "\n=== Director Wikidata enrich dry run (#{rows.size} proposals) ===\n"
      header = format(
        "%-28s | %-6s | %-6s | %-16s | %-5s | %-40s | %s",
        "Director", "Birth", "Death", "Nationality", "Photo", "Bio preview", "Source URL"
      )
      puts header
      puts "-" * header.length

      rows.each do |row|
        puts format(
          "%-28s | %-6s | %-6s | %-16s | %-5s | %-40s | %s",
          row[:name].slice(0, 28),
          row[:birth_year].to_s.presence || "-",
          row[:death_year].to_s.presence || "-",
          row[:nationality].to_s.slice(0, 16).presence || "-",
          row[:has_photo] ? "yes" : "no",
          row[:bio_preview].to_s.slice(0, 40).presence || "-",
          row[:source_url].to_s.slice(0, 50).presence || "-"
        )
      end
      puts ""
    end

    def acceptable_director_match?(entity)
      return false unless human?(entity)

      occupation_qids(entity).intersect?(DIRECTOR_OCCUPATION_QIDS) ||
        entity_description(entity).to_s.match?(DIRECTOR_DESCRIPTION_PATTERN)
    end

    def search_wikidata(name)
      response = wikidata_get(
        action: "wbsearchentities",
        search: name,
        language: "lt",
        uselang: "lt",
        type: "item",
        limit: 5,
        format: "json"
      )
      hits = response.dig("search") || []
      return hits.first if hits.any?

      sleep DELAY_BETWEEN_REQUESTS
      response = wikidata_get(
        action: "wbsearchentities",
        search: name,
        language: "en",
        uselang: "en",
        type: "item",
        limit: 5,
        format: "json"
      )
      (response.dig("search") || []).first
    end

    def fetch_entity(qid)
      response = wikidata_get(
        action: "wbgetentities",
        ids: qid,
        props: "descriptions|claims|sitelinks|labels",
        languages: "lt|en",
        format: "json"
      )
      response.dig("entities", qid)
    end

    def wikidata_get(params)
      JSON.parse(@http.get(WIKIDATA_API, params).body)
    end

    def human?(entity)
      instance_of_qids(entity).include?(HUMAN_QID)
    end

    def instance_of_qids(entity)
      claim_entity_ids(entity, "P31")
    end

    def occupation_qids(entity)
      claim_entity_ids(entity, "P106")
    end

    def image_filename(entity)
      claim_string_values(entity, "P18").first
    end

    def year_from_claim(entity, property)
      time = entity.dig("claims", property, 0, "mainsnak", "datavalue", "value", "time")
      return nil if time.blank?

      match = time.match(/[+-]?(\d{4})/)
      match ? match[1].to_i : nil
    end

    def resolve_nationality(entity)
      nationality_from_description(entity) || nationality_from_citizenship(entity)
    end

    def nationality_from_description(entity)
      description = entity.dig("descriptions", "en", "value") ||
                    entity.dig("descriptions", "lt", "value")
      return nil if description.blank?

      adjective = leading_nationality_adjective(description)
      return nil if adjective.blank?

      map_nationality_adjective(adjective)
    end

    def leading_nationality_adjective(description)
      if description.match?(/\Alietuvių\b/i)
        return "lietuvių"
      end

      match = description.match(/\A([A-Za-zÀ-ÿ]+(?:-[A-Za-zÀ-ÿ]+)?)\b/)
      return nil unless match

      match[1].split("-").first
    end

    def map_nationality_adjective(adjective)
      key = adjective.to_s.downcase
      NATIONALITY_ADJECTIVE_MAP[key]
    end

    def nationality_from_citizenship(entity)
      claim_entity_ids(entity, "P27").each do |country_qid|
        next if DISSOLVED_STATE_QIDS.include?(country_qid)

        country = fetch_entity(country_qid)
        next unless country

        label = entity_label(country)
        next if label.blank?
        next if dissolved_nationality_label?(label)

        return label
      end

      nil
    end

    def dissolved_nationality_label?(label)
      normalized = label.to_s.downcase
      normalized.include?("soviet") || normalized.include?("sovietų")
    end

    def entity_label(entity)
      entity.dig("labels", "lt", "value") ||
        entity.dig("labels", "en", "value")
    end

    def entity_description(entity)
      entity.dig("descriptions", "lt", "value") ||
        entity.dig("descriptions", "en", "value")
    end

    def wiki_title(entity)
      preferred_wiki_sitelink(entity)&.last
    end

    def preferred_wiki_sitelink(entity)
      sitelinks = entity["sitelinks"] || {}
      if sitelinks["ltwiki"]
        ["lt", sitelinks["ltwiki"]["title"]]
      elsif sitelinks["enwiki"]
        ["en", sitelinks["enwiki"]["title"]]
      end
    end

    def wikipedia_page_url(lang, title)
      return nil if lang.blank? || title.blank?

      "https://#{lang}.wikipedia.org/wiki/#{wiki_path_segment(title)}"
    end

    def fetch_wikipedia_extract(lang, title)
      return nil if lang.blank? || title.blank?

      url = "https://#{lang}.wikipedia.org/api/rest_v1/page/summary/#{wiki_path_segment(title)}"
      sleep DELAY_BETWEEN_REQUESTS
      response = @http.get(url)
      return nil unless response.status == 200

      JSON.parse(response.body)["extract"].presence
    rescue JSON::ParserError, Faraday::Error => e
      Rails.logger.warn("[DirectorWikidataEnricher] Wikipedia summary failed for #{title}: #{e.message}")
      nil
    end

    def commons_photo_url(filename)
      encoded = CGI.escape(filename.tr(" ", "_"))
      "#{COMMONS_FILE_PATH}#{encoded}?width=400"
    end

    def commons_photo_credit(filename)
      response = JSON.parse(
        @http.get(
          COMMONS_API,
          action: "query",
          titles: "File:#{filename}",
          prop: "imageinfo",
          iiprop: "extmetadata",
          format: "json"
        ).body
      )

      metadata = response.dig("query", "pages")&.values&.first
                          &.dig("imageinfo", 0, "extmetadata") || {}
      artist = strip_html(metadata.dig("Artist", "value").to_s).presence || "Unknown"
      license = metadata.dig("LicenseShortName", "value").to_s.presence || "Unknown"
      "Wikimedia Commons / #{artist} (#{license})"
    rescue JSON::ParserError, Faraday::Error => e
      Rails.logger.warn("[DirectorWikidataEnricher] Commons metadata failed for #{filename}: #{e.message}")
      "Wikimedia Commons"
    end

    def resolve_death_year(director, entity)
      from_db = director.read_attribute(:death_year)
      from_wikidata = year_from_claim(entity, "P570")
      resolved = from_db.presence || from_wikidata

      Rails.logger.info(
        "[DirectorWikidataEnricher] death_year for #{director.name}: " \
        "resolved=#{resolved.inspect} db=#{from_db.inspect} wikidata=#{from_wikidata.inspect}"
      )

      resolved
    end

    def generate_lithuanian_bio(extract, director_name, death_year: nil)
      return nil if extract.blank?

      deceased = death_year.present?
      bio = request_lithuanian_bio(extract, director_name, death_year:, deceased:, emphatic: false)

      if deceased && bio.present? && bio_uses_present_tense?(bio)
        Rails.logger.warn(
          "[DirectorWikidataEnricher] Deceased bio used present tense for #{director_name} " \
          "(death_year=#{death_year}), retrying with emphatic past-tense prompt"
        )
        bio = request_lithuanian_bio(extract, director_name, death_year:, deceased:, emphatic: true)
        if bio.present? && bio_uses_present_tense?(bio)
          Rails.logger.error(
            "[DirectorWikidataEnricher] Deceased bio still present tense after retry: #{director_name} " \
            "(death_year=#{death_year}) preview=#{bio.slice(0, 80).inspect}"
          )
        end
      end

      bio
    end

    def request_lithuanian_bio(extract, director_name, death_year:, deceased:, emphatic:)
      system = bio_system_prompt(deceased:, death_year:, emphatic:)
      life_status = deceased ? "Miręs (mirties metai: #{death_year})" : "Gyvas"
      user = <<~USR
        Režisierius: #{director_name}
        Gyvenimo statusas: #{life_status}
        Vikipedijos ištrauka:
        #{extract}
      USR

      claude_client.complete(
        system: system,
        user: user,
        max_tokens: 300,
        model: BIO_MODEL
      ).to_s.strip.presence
    end

    def bio_system_prompt(deceased:, death_year:, emphatic:)
      if deceased
        past_lead = if emphatic
          <<~LEAD
            SVARBU: asmuo MIRĘS (mirties metai: #{death_year}). VISĄ tekstą rašyk TIK būtuoju laiku (buvo, kūrė, pastatė, dirbo).
            Jokio esamojo laiko — ne „yra“, ne „kuria“, ne „derina“, ne „dirba“.
          LEAD
        else
          <<~LEAD
            SVARBU: asmuo MIRĘS. VISĄ biografiją rašyk būtuoju laiku (buvo, kūrė, pastatė, dirbo).
            Jokio esamojo laiko (ne 'yra', ne 'kuria', ne 'derina').
          LEAD
        end

        <<~SYS
          #{past_lead.strip}

          Parašyk 2–3 sakinių NEUTRALŲ, FAKTIŠKĄ biografijos santrauką TAISYKLINGA lietuvių kalba.
          Naudok tikslią teatro terminiją (režisierius pastatė/sukūrė spektaklius — NE "dirigavo").
          Tinkami linksniai ir giminė. Jokių rašybos klaidų. Remkis TIK pateiktu tekstu, nieko nepridėk.
          Parafrazuok savais žodžiais (ne kopija). Grąžink tik bio tekstą, be antraštės ar paaiškinimų.
        SYS
      else
        <<~SYS
          Parašyk 2–3 sakinių NEUTRALŲ, FAKTIŠKĄ biografijos santrauką TAISYKLINGA lietuvių kalba.
          Naudok tikslią teatro terminiją (režisierius pastatė/sukūrė spektaklius — NE "dirigavo").
          Tinkami linksniai ir giminė. Jokių rašybos klaidų. Remkis TIK pateiktu tekstu, nieko nepridėk.
          Parafrazuok savais žodžiais (ne kopija). Asmuo gyvas — rašyk esamuoju laiku („yra“, „kuria“, „pastato").
          Grąžink tik bio tekstą, be antraštės ar paaiškinimų.
        SYS
      end
    end

    def bio_uses_present_tense?(bio)
      bio.match?(BIO_PRESENT_TENSE_PATTERN)
    end

    def claude_client
      @claude_client ||= ClaudeClient.new
    end

    def claim_entity_ids(entity, property)
      (entity.dig("claims", property) || []).filter_map do |claim|
        value = claim.dig("mainsnak", "datavalue", "value")
        value["id"] if value.is_a?(Hash) && value["id"]
      end
    end

    def claim_string_values(entity, property)
      (entity.dig("claims", property) || []).filter_map do |claim|
        value = claim.dig("mainsnak", "datavalue", "value")
        value if value.is_a?(String) && value.present?
      end
    end

    def wiki_path_segment(title)
      CGI.escape(title.tr(" ", "_"))
    end

    def strip_html(text)
      text.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    end

    def log_skip(name, reason)
      Rails.logger.warn("[DirectorWikidataEnricher] #{reason}: #{name}")
    end
  end
end
