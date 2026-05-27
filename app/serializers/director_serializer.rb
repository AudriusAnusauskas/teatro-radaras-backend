class DirectorSerializer
    def self.list(director)
      summary(director).merge(
        latest_production: serialize_latest_production(director)
      )
    end
  
    def self.detail(director)
      summary(director).merge(
        birthYear:     director.birth_year,
        deathYear:     director.death_year,
        bio:           director.bio,
        notableWorks:  director.notable_works,
        photoUrl:      director.photo_url,
        photoCredit:   director.photo_credit,
        sourceUrl:     director.source_url,
        productions:   director.productions.map { |p| ProductionSerializer.list(p) }
      )
    end

    def self.summary(director)
      {
        slug:              director.slug,
        name:              director.name,
        nationality:       director.nationality,
        photo_url:         director.photo_url,
        productions_count: director.productions.size
      }
    end

    def self.serialize_latest_production(director)
      production = director.productions.max_by { |p| p.premiere_date || p.created_at.to_date }
      return nil unless production

      {
        slug:               production.slug,
        title:              production.title,
        theater_short_name: production.theater.short_name,
        premiere_year:      production.premiere_date&.year
      }
    end
  end
