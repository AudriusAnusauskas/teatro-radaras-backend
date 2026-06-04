module Scrapers
  class MenufakturaProductionMatcher
    # Class-level cache so repeated productions sharing a letter don't refetch.
    @letter_cache = {}

    class << self
      attr_accessor :letter_cache

      def reset_cache!
        @letter_cache = {}
      end
    end

    # Lithuanian diacritic letters folded to their ASCII bucket, since
    # menufaktura.lt may file e.g. "Įstabioji…" under "I" or "Šokis" under "S".
    DIACRITIC_FOLD = {
      "Ą" => "A", "Č" => "C", "Ę" => "E", "Ė" => "E", "Į" => "I",
      "Š" => "S", "Ū" => "U", "Ų" => "U", "Ī" => "I", "Ž" => "Z"
    }.freeze

    def initialize(catalog_scraper: MenufakturaCatalogScraper.new, client: nil)
      @catalog = catalog_scraper
      @client = client
    end

    # Returns the menufaktura.lt production ID (Integer) or nil if no confident match.
    def find_id(production)
      title = production.title.to_s.strip
      return nil if title.blank?

      candidates = gather_candidates(title)
      return nil if candidates.empty?

      exact = candidates.find { |candidate| normalize(candidate[:title]) == normalize(title) }
      return exact[:menufaktura_id] if exact

      claude_match(production, candidates)
    end

    private

    # Merge the primary first-letter bucket with fallback buckets — the
    # ASCII-folded first letter and the "<" digit/symbol bucket — so a title
    # filed under a different leading character is still considered. Primary
    # bucket entries are kept first; deduped by menufaktura_id.
    def gather_candidates(title)
      bucket_letters(title)
        .flat_map { |letter| candidates_for(letter) }
        .uniq { |candidate| candidate[:menufaktura_id] }
    end

    def bucket_letters(title)
      primary = first_letter(title)
      [primary, ascii_fold(primary), "<"].uniq
    end

    def ascii_fold(letter)
      DIACRITIC_FOLD.fetch(letter, letter)
    end

    def candidates_for(letter)
      self.class.letter_cache[letter] ||= @catalog.fetch_letter(letter)
    end

    def first_letter(title)
      char = title.to_s.strip.slice(0).to_s.upcase
      char.match?(/[[:alpha:]]/) ? char : "<"
    end

    # Lowercase, strip Lithuanian/ASCII quotes and collapse whitespace.
    def normalize(str)
      str.to_s.downcase.gsub(/[„“”"']/, "").gsub(/\s+/, " ").strip
    end

    # Fallback: let Claude pick the matching production from the candidate list.
    def claude_match(production, candidates)
      list = candidates.map { |c| "#{c[:menufaktura_id]}: #{c[:title]}" }.join("\n")
      director_line = production.director&.name.present? ? "\nRežisierius: #{production.director.name}" : ""

      system = <<~SYS
        Tu padedi sugretinti teatro spektaklį iš mūsų duomenų bazės su menufaktura.lt sąrašo įrašu.
        Iš kandidatų pasirink TIK tą, kuris yra tas pats spektaklis (tas pats pastatymas/pavadinimas).
        Režisierius padeda atskirti spektaklius su tuo pačiu ar panašiu pavadinimu (skirtingi pastatymai).
        Jei nė vienas aiškiai nesutampa — grąžink null.
        Atsakyk TIK JSON formatu, be jokio papildomo teksto:
        {"menufaktura_id": <id sveikasis skaičius> arba null}
      SYS

      user = <<~USR
        Mūsų spektaklis: #{production.title}#{director_line}
        Teatras: #{production.theater&.name}
        Kandidatai (id: pavadinimas):
        #{list}
      USR

      raw = client.complete(system: system, user: user, max_tokens: 100)
      id = raw.to_s[/"menufaktura_id"\s*:\s*(\d+)/, 1]&.to_i
      return nil unless id

      candidates.any? { |c| c[:menufaktura_id] == id } ? id : nil
    rescue ClaudeClient::RateLimitError
      raise
    rescue StandardError => e
      Rails.logger.error("[MenufakturaProductionMatcher] Claude match error for '#{production.title}': #{e.message}")
      nil
    end

    def client
      @client ||= ClaudeClient.new
    end
  end
end
