module Scrapers
  class VmtCatalogImporter < BaseCatalogImporter
    THEATER_SLUG = "valstybinis-vilniaus-mazasis-teatras"
    DIRECTOR_COUNTRY_SUFFIX_PATTERN = /\s*\([^)]+\)\z/

    private

    def production_attributes(data, director)
      genre, creative_team = resolve_genre_and_creative_team(data)

      {
        title: data[:title],
        director: director,
        author: data[:author],
        translator: data[:translator],
        genre: genre,
        age_rating: data[:age_rating],
        premiere_date: parse_premiere_date(data[:premiere_date]),
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        description: data[:description],
        cast_members: data[:cast] || [],
        creative_team: creative_team,
        poster_url: data[:poster_url],
        is_guest: data[:is_guest] == true,
        status: "active"
      }
    end

    def resolve_genre_and_creative_team(data)
      creative_team = (data[:creative_team] || {}).stringify_keys.dup
      genre = data[:genre]

      if data[:is_guest] && guest_theater_name?(genre)
        creative_team["Svečių teatras"] = genre
        genre = nil
      end

      [genre, creative_team]
    end

    def guest_theater_name?(genre)
      return false if genre.blank?

      genre.match?(/\ATeatras\b/i) || genre.include?("„") || genre.include?('"')
    end

    def strip_director_suffix(name)
      name.to_s.gsub(DIRECTOR_COUNTRY_SUFFIX_PATTERN, "").strip
    end
  end
end
