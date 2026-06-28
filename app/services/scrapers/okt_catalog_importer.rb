module Scrapers
  class OktCatalogImporter < BaseCatalogImporter
    THEATER_SLUG = "oskaro-korsunovo-teatras"

    DIRECTOR_SEPARATOR_PATTERN = /\s+ir\s+|\s*&\s*/i

    private

    def first_director_name(raw)
      return nil if raw.blank?

      normalized = raw.gsub(DIRECTOR_SEPARATOR_PATTERN, ", ")
      super(normalized)
    end

    def production_attributes(data, director)
      {
        title: data[:title],
        director: director,
        author: resolve_author(data[:author]),
        translator: data[:translator],
        premiere_date: parse_premiere_date(data[:premiere_date]),
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        description: data[:description],
        cast_members: data[:cast] || [],
        creative_team: data[:creative_team] || {},
        poster_url: data[:poster_url],
        status: "active"
      }.compact
    end
  end
end
