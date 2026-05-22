class DirectorSerializer
    def self.list(director)
      {
        slug:              director.slug,
        name:              director.name,
        nationality:       director.nationality,
        photo_url:         director.photo_url,
        productions_count: director.productions.size
      }
    end
  
    def self.detail(director)
      list(director).merge(
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
  end
