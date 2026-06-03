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

    def initialize(catalog_scraper: MenufakturaCatalogScraper.new, client: nil)
      @catalog = catalog_scraper
      @client = client
    end

    # Returns the menufaktura.lt production ID (Integer) or nil if no confident match.
    def find_id(production)
      title = production.title.to_s.strip
      return nil if title.blank?

      candidates = candidates_for(first_letter(title))
      return nil if candidates.empty?

      exact = candidates.find { |candidate| normalize(candidate[:title]) == normalize(title) }
      return exact[:menufaktura_id] if exact

      claude_match(production, candidates)
    end

    private

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

      system = <<~SYS
        Tu padedi sugretinti teatro spektaklį iš mūsų duomenų bazės su menufaktura.lt sąrašo įrašu.
        Iš kandidatų pasirink TIK tą, kuris yra tas pats spektaklis (tas pats pastatymas/pavadinimas).
        Jei nė vienas aiškiai nesutampa — grąžink null.
        Atsakyk TIK JSON formatu, be jokio papildomo teksto:
        {"menufaktura_id": <id sveikasis skaičius> arba null}
      SYS

      user = <<~USR
        Mūsų spektaklis: #{production.title}
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
