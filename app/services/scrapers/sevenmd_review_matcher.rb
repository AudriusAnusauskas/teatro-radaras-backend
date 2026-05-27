module Scrapers
  class SevenmdReviewMatcher
    def initialize(scraped_review)
      @scraped = scraped_review
    end

    # Returns { production: Production|nil, confidence: Float, status: Symbol, signal: String }
    def match
      return unmatched("no tags") if @scraped[:tags].blank?

      production_candidates = find_production_candidates_by_tags

      case production_candidates.size
      when 0
        unmatched("no production tag matches")
      when 1
        production = production_candidates.first
        if theater_verified?(production)
          matched(production, 1.0, "tag exact match + theater verified")
        else
          matched(production, 0.7, "tag exact match (theater not verified)")
        end
      else
        disambiguated = production_candidates.find { |production| theater_verified?(production) }
        return matched(disambiguated, 0.9, "multiple candidates, theater disambiguated") if disambiguated

        by_director = production_candidates.find do |production|
          production.director && @scraped[:tags].any? { |tag| tag.casecmp(production.director.name) == 0 }
        end
        return matched(by_director, 0.7, "multiple candidates, director disambiguated") if by_director

        unmatched("multiple production candidates, no disambiguation")
      end
    end

    private

    def find_production_candidates_by_tags
      @scraped[:tags].flat_map do |tag|
        Production.where("LOWER(title) = ?", tag.to_s.downcase).to_a
      end.uniq
    end

    def theater_verified?(production)
      return false unless production.theater

      @scraped[:tags].any? { |tag| tag.casecmp(production.theater.name) == 0 }
    end

    def matched(production, confidence, signal)
      { production: production, confidence: confidence, status: :matched, signal: signal }
    end

    def unmatched(reason)
      { production: nil, confidence: 0.0, status: :unmatched, signal: reason }
    end
  end
end
