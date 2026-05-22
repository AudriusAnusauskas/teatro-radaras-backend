class TheaterSerializer
    def self.list(theater)
      {
        slug:              theater.slug,
        name:              theater.name,
        short_name:        theater.short_name,
        city:              theater.city,
        photo_url:         theater.photo_url,
        founded_year:      theater.founded_year,
        productions_count: theater.productions.size
      }
    end
  
    def self.detail(theater)
      list(theater).merge(
        address:        theater.address,
        coordinates:    {
          lat: theater.latitude,
          lng: theater.longitude
        },
        phone:          theater.phone,
        foundedYear:    theater.founded_year,
        currentSeason:  theater.current_season,
        websiteUrl:     theater.website_url,
        venues:         theater.venues,
        description:    theater.description,
        photoUrl:       theater.photo_url,
        photoCredit:    theater.photo_credit,
        social:         theater.social,
        productions:    theater.productions.map { |p| ProductionSerializer.list(p) }
      )
    end
  end
