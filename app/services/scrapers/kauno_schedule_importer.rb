module Scrapers
  class KaunoScheduleImporter < BaseScheduleImporter
    THEATER_SLUG = "nacionalinis-kauno-dramos-teatras"
    VENUE = "Nacionalinis Kauno dramos teatras"
    CITY = "Kaunas"

    private

    def theater_slug
      THEATER_SLUG
    end

    def city_for(_data)
      CITY
    end

    def theater
      @theater ||= Theater.find_by!(slug: THEATER_SLUG)
    end

    def find_production(data)
      return nil if data[:source_url].blank?

      Production.find_by(theater_id: theater.id, source_url: data[:source_url])
    end

    def import_one(data)
      production = find_production(data)
      unless production
        Rails.logger.warn("[KaunoScheduleImporter] no production match: #{data[:source_url]}")
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
