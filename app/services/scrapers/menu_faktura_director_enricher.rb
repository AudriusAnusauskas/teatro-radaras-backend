require "json"
require "nokogiri"
require "faraday/retry"

module Scrapers
  class MenuFakturaDirectorEnricher
    BASE_URL = "https://menufaktura.lt"
    USER_AGENT = "TeatroRadarasBot/1.0 (+https://teatroradaras.lt; director bio enrichment)"
    DELAY_BETWEEN_REQUESTS = 0.3
    BIO_MODEL = "claude-sonnet-4-5-20250929"
    CREATOR_PATH = "/kurejas"
    WP_API_PATH = "/wp-json/wp/v2/kurejas"

    BIO_PRESENT_TENSE_PATTERN = /\b(yra|kuria|dirba|derina|pastato|režisuoja|žaidžia|kurio)\b/i
    BIRTH_YEAR_PATTERN = /gim[ėe]\s+(\d{4})/i
    DEATH_YEAR_PATTERN = /mir[ėe]\b.*?(\d{4})/i
    AWARDS_PREFIX_PATTERN = /\ASvarbiausi apdovanojimai/i

    def initialize(http: nil, claude_client: nil)
      @http = http || Faraday.new do |f|
        f.headers["User-Agent"] = USER_AGENT
        f.request :retry, max: 3, interval: 1, backoff_factor: 2
      end
      @claude_client = claude_client
    end

    # READ-ONLY: try menufaktura.lt/kurejas/{slug}/ for every blank-bio director.
    def scout
      rows = directors_with_blank_bio.map.with_index do |director, index|
        sleep DELAY_BETWEEN_REQUESTS if index.positive?
        scout_director(director)
      rescue StandardError => e
        Rails.logger.error("[MenuFakturaDirectorEnricher] Scout failed #{director.name}: #{e.message}")
        scout_row(director, found: false, note: e.message)
      end

      print_scout_table(rows)
      print_coverage_summary(rows)
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
        Rails.logger.error("[MenuFakturaDirectorEnricher] Enrich failed #{director.name}: #{e.message}")
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
      page = resolve_creator_page(director)
      return scout_row(director, found: false, note: "not found") unless page

      parsed = parse_creator_page(page[:doc], page[:url])
      scout_row(
        director,
        found: true,
        slug: page[:slug],
        parsed_name: parsed[:name],
        creator_type: parsed[:creator_type],
        birth_year: parsed[:birth_year],
        death_year: parsed[:death_year],
        bio_preview: parsed[:bio_source].to_s.slice(0, 80)
      )
    end

    def scout_row(director, found:, **fields)
      {
        name: director.name,
        slug: director.slug,
        found: found,
        mf_slug: fields[:slug] || "-",
        parsed_name: fields[:parsed_name] || "-",
        creator_type: fields[:creator_type] || "-",
        birth_year: fields[:birth_year] || "-",
        death_year: fields[:death_year] || "-",
        bio_preview: fields[:bio_preview] || "-",
        note: fields[:note]
      }
    end

    def print_scout_table(rows)
      puts "\n=== MenuFaktura director scout (#{rows.size} directors with blank bio) ===\n"
      header = format(
        "%-26s | %-5s | %-24s | %-24s | %-12s | %-6s | %-6s | %s",
        "Director", "Found", "MF slug", "Parsed name", "Type", "Birth", "Death", "Bio preview"
      )
      puts header
      puts "-" * header.length

      rows.each do |row|
        if row[:note] && !row[:found]
          puts "#{row[:name].slice(0, 26).ljust(26)} | no    | #{"-".ljust(24)} | #{row[:note].slice(0, 24).ljust(24)} | #{"-".ljust(12)} | #{"-".ljust(6)} | #{"-".ljust(6)} | -"
          next
        end

        puts format(
          "%-26s | %-5s | %-24s | %-24s | %-12s | %-6s | %-6s | %s",
          row[:name].slice(0, 26),
          row[:found] ? "yes" : "no",
          row[:mf_slug].to_s.slice(0, 24),
          row[:parsed_name].to_s.slice(0, 24),
          row[:creator_type].to_s.slice(0, 12),
          row[:birth_year].to_s,
          row[:death_year].to_s,
          row[:bio_preview].to_s.slice(0, 60)
        )
      end
      puts ""
    end

    def print_coverage_summary(rows)
      found = rows.count { |r| r[:found] }
      missed = rows.size - found
      slug_hits = rows.count { |r| r[:found] && r[:mf_slug] == r[:slug] }
      fallback_hits = found - slug_hits

      puts "Coverage: #{found}/#{rows.size} found (#{slug_hits} slug match, #{fallback_hits} name fallback), #{missed} missed"
      puts ""
    end

    def process_enrichment(director, dry_run:, results:)
      page = resolve_creator_page(director)
      unless page
        log_skip(director.name, "menufaktura page not found")
        results[:skipped] += 1
        return
      end

      parsed = parse_creator_page(page[:doc], page[:url])
      proposal = build_enrichment_proposal(director, parsed)
      if proposal.empty?
        log_skip(director.name, "no blank fields to fill")
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

    def build_enrichment_proposal(director, parsed)
      death_year = director.death_year.blank? ? parsed[:death_year] : nil
      birth_year = director.birth_year.blank? ? parsed[:birth_year] : nil
      bio = if director.bio.blank? && parsed[:bio_source].present?
              generate_lithuanian_bio(parsed[:bio_source], director.name, death_year: death_year || parsed[:death_year])
            end

      {
        birth_year: birth_year,
        death_year: death_year,
        bio: bio,
        source_url: parsed[:source_url]
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
        bio_preview: proposal[:bio].to_s.slice(0, 120).presence,
        source_url: proposal[:source_url]
      }
    end

    def print_dry_run_table(rows)
      puts "\n=== MenuFaktura director enrich dry run (#{rows.size} proposals) ===\n"
      header = format("%-28s | %-6s | %-6s | %-40s | %s", "Director", "Birth", "Death", "Bio preview", "Source URL")
      puts header
      puts "-" * header.length

      rows.each do |row|
        puts format(
          "%-28s | %-6s | %-6s | %-40s | %s",
          row[:name].slice(0, 28),
          row[:birth_year].to_s.presence || "-",
          row[:death_year].to_s.presence || "-",
          row[:bio_preview].to_s.slice(0, 40).presence || "-",
          row[:source_url].to_s.slice(0, 50).presence || "-"
        )
      end
      puts ""
    end

    def resolve_creator_page(director)
      slug_doc = fetch_creator_doc(director.slug)
      if slug_doc && valid_creator_page?(slug_doc)
        parsed = parse_creator_page(slug_doc, creator_url(director.slug))
        return { doc: slug_doc, url: creator_url(director.slug), slug: director.slug } if names_match?(parsed[:name], director.name)
      end

      alt_slug = find_slug_by_name(director.name)
      return nil if alt_slug.blank?

      alt_doc = fetch_creator_doc(alt_slug)
      return nil unless alt_doc && valid_creator_page?(alt_doc)

      parsed = parse_creator_page(alt_doc, creator_url(alt_slug))
      return nil unless names_match?(parsed[:name], director.name)

      { doc: alt_doc, url: creator_url(alt_slug), slug: alt_slug }
    end

    def fetch_creator_doc(slug)
      response = @http.get(creator_url(slug))
      return nil unless response.status == 200

      Nokogiri::HTML(response.body)
    rescue Faraday::Error => e
      Rails.logger.warn("[MenuFakturaDirectorEnricher] HTTP failed #{creator_url(slug)}: #{e.message}")
      nil
    end

    def find_slug_by_name(name)
      response = @http.get("#{BASE_URL}#{WP_API_PATH}", { search: name, per_page: 20 })
      return nil unless response.success?

      candidates = JSON.parse(response.body)
      return candidates.first["slug"] if candidates.one?

      hit = candidates.find { |row| names_match?(row.dig("title", "rendered"), name) }
      hit&.dig("slug")
    rescue JSON::ParserError, Faraday::Error => e
      Rails.logger.warn("[MenuFakturaDirectorEnricher] Name search failed for #{name}: #{e.message}")
      nil
    end

    def parse_creator_page(doc, source_url)
      block = doc.at_css(".block-director")
      bio_source = extract_bio_source_text(block)
      awards = extract_awards_text(block)

      {
        name: block&.at_css(".title.h1")&.text&.strip,
        creator_type: block&.at_css(".title.purple")&.text&.strip,
        birth_year: bio_source[BIRTH_YEAR_PATTERN, 1]&.to_i,
        death_year: bio_source[DEATH_YEAR_PATTERN, 1]&.to_i,
        bio_source: bio_source,
        awards: awards,
        works_count: block&.css(".list-stripped .item")&.size.to_i,
        source_url: source_url
      }
    end

    def valid_creator_page?(doc)
      block = doc.at_css(".block-director")
      return false unless block

      name = block.at_css(".title.h1")&.text&.strip
      return false if name.blank?

      bio_present = extract_bio_source_text(block).present?
      works_present = block.at_css(".h2.before-list")&.text.to_s.match?(/Darbai teatre/i) &&
                      block.css(".list-stripped .item").any?
      bio_present || works_present
    end

    def extract_bio_source_text(block)
      return "" unless block

      paragraphs = block.css(".wysiwyg p").map { |p| clean_text(p.text) }.reject(&:blank?)
      paragraphs.reject { |text| text.match?(AWARDS_PREFIX_PATTERN) }.join("\n\n")
    end

    def extract_awards_text(block)
      return nil unless block

      paragraph = block.css(".wysiwyg p").map { |p| clean_text(p.text) }.find { |text| text.match?(AWARDS_PREFIX_PATTERN) }
      paragraph&.sub(/\ASvarbiausi apdovanojimai:\s*/i, "")&.strip.presence
    end

    def creator_url(slug)
      "#{BASE_URL}#{CREATOR_PATH}/#{slug}/"
    end

    def names_match?(page_name, director_name)
      return false if page_name.blank? || director_name.blank?

      normalized_page = normalize_compare(page_name)
      normalized_director = normalize_compare(director_name)
      return true if normalized_page == normalized_director

      page_tokens = normalized_page.split(" ")
      director_tokens = normalized_director.split(" ")
      return false if page_tokens.empty? || director_tokens.empty?

      surname_match?(page_tokens.last, director_tokens.last) &&
        given_name_match?(page_tokens.first, director_tokens.first)
    end

    def given_name_match?(left, right)
      return true if left == right
      return true if left.start_with?(right.first(4)) || right.start_with?(left.first(4))

      false
    end

    def surname_match?(left, right)
      return true if left == right
      return true if left.start_with?(right) || right.start_with?(left)

      false
    end

    def normalize_compare(text)
      text.to_s.downcase
          .unicode_normalize(:nfkd)
          .encode("ASCII", replace: "")
          .gsub(/[^a-z0-9]+/, " ")
          .squish
    end

    def generate_lithuanian_bio(source_text, director_name, death_year: nil)
      return nil if source_text.blank?

      deceased = death_year.present?
      bio = request_lithuanian_bio(source_text, director_name, death_year:, deceased:, emphatic: false)

      if deceased && bio.present? && bio.match?(BIO_PRESENT_TENSE_PATTERN)
        bio = request_lithuanian_bio(source_text, director_name, death_year:, deceased:, emphatic: true)
      end

      bio
    end

    def request_lithuanian_bio(source_text, director_name, death_year:, deceased:, emphatic:)
      system = bio_system_prompt(deceased:, death_year:, emphatic:)
      life_status = deceased ? "Miręs (mirties metai: #{death_year})" : "Gyvas"
      user = <<~USR
        Kūrėjas: #{director_name}
        Gyvenimo statusas: #{life_status}
        Menufaktūra.lt biografijos tekstas (autorių teisių saugomas — tik parafrazuok):
        #{source_text}
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
                      "SVARBU: asmuo MIRĘS (mirties metai: #{death_year}). VISĄ tekstą rašyk TIK būtuoju laiku."
                    else
                      "SVARBU: asmuo MIRĘS. VISĄ biografiją rašyk būtuoju laiku."
                    end

        <<~SYS
          #{past_lead}
          Parašyk 2–3 sakinių NEUTRALŲ, FAKTIŠKĄ biografijos santrauką TAISYKLINGA lietuvių kalba.
          Naudok tikslią teatro terminiją. Remkis TIK pateiktu tekstu. Parafrazuok savais žodžiais — NE kopijuok pažodžiui.
          Grąžink tik bio tekstą.
        SYS
      else
        <<~SYS
          Parašyk 2–3 sakinių NEUTRALŲ, FAKTIŠKĄ biografijos santrauką TAISYKLINGA lietuvių kalba.
          Naudok tikslią teatro terminiją. Remkis TIK pateiktu tekstu. Parafrazuok savais žodžiais — NE kopijuok pažodžiui.
          Asmuo gyvas — rašyk esamuoju laiku. Grąžink tik bio tekstą.
        SYS
      end
    end

    def claude_client
      @claude_client ||= ClaudeClient.new
    end

    def clean_text(text)
      text.to_s.gsub(/\u00A0/, " ").squish
    end

    def log_skip(name, reason)
      Rails.logger.warn("[MenuFakturaDirectorEnricher] #{reason}: #{name}")
    end
  end
end
