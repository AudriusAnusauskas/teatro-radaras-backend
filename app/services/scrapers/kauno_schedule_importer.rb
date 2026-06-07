module Scrapers
  class KaunoScheduleImporter < BaseScheduleImporter
    THEATER_SLUG = "nacionalinis-kauno-dramos-teatras"
    VENUE = "Nacionalinis Kauno dramos teatras"
    CITY = "Kaunas"

    private

    def theater_slug
      THEATER_SLUG
    end

    def slug_key
      :slug
    end

    def city_for(_data)
      CITY
    end

    def import_one(data)
      production = find_production(data)
      unless production
        Rails.logger.warn("[KaunoScheduleImporter] no production match: #{data[:slug]}")
        return :skipped
      end

      if production.theater&.slug != theater_slug
        Rails.logger.warn(
          "[KaunoScheduleImporter] Skipping screening - wrong theater (#{production.theater&.slug}) " \
          "for #{data.slice(:slug).inspect}"
        )
        return :skipped
      end

      upsert_screening(production, data)
    end

    def upsert_screening(production, data)
      screening = Screening.find_or_initialize_by(
        production_id: production.id,
        starts_at: data[:starts_at]
      )

      is_new = screening.new_record?

      screening.assign_attributes(
        venue: VENUE,
        city: CITY,
        ticket_url: data[:ticket_url],
        is_premiere: data[:is_premiere] == true
      )

      screening.save!
      is_new ? :created : :updated
    end
  end
end
