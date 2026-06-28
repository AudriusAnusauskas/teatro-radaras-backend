module Scrapers
  class JaunimoTeatrasCatalogImporter < BaseCatalogImporter
    THEATER_SLUG = "valstybinis-jaunimo-teatras"

    private

    def production_attributes(data, director)
      {
        title: data[:title],
        director: director,
        author: resolve_author(data[:author]),
        premiere_date: parse_premiere_date(data[:premiere_date]),
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        age_rating: data[:age_rating],
        description: data[:description],
        poster_url: data[:poster_url],
        cast_members: data[:cast] || [],
        status: "active"
      }.compact
    end
  end
end
