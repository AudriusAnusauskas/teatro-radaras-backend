module Scrapers
  class MiltinioScheduleImporter < BaseScheduleImporter
    THEATER_SLUG = "juozo-miltinio-dramos-teatras"
    CITY = "Panevėžys"

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

    def import_one(data)
      production = find_production(data)
      unless production
        Rails.logger.warn("[MiltinioScheduleImporter] no production match: #{data[:source_url]}")
        return :skipped
      end

      upsert_screening(production, data)
    end

    def find_production(data)
      return nil if data[:source_url].blank?

      production = Production.find_by(theater_id: theater.id, source_url: data[:source_url])
      return production if production

      if data[:title].present?
        production = find_by_normalized_title(data[:title])
        return production if production
      end

      nil
    end

    def find_by_normalized_title(title)
      target = normalize_title(title)
      return nil if target.blank?

      theater.productions.find do |production|
        normalize_title(production.title) == target
      end
    end

    def normalize_title(title)
      ActiveSupport::Inflector.transliterate(title.to_s)
                             .downcase
                             .gsub(/^premjera\.?\s*/, "")
                             .gsub(/[^a-z0-9]+/, " ")
                             .squish
    end

    def upsert_screening(production, data)
      screening = Screening.find_or_initialize_by(
        production_id: production.id,
        starts_at: data[:starts_at]
      )

      is_new = screening.new_record?

      screening.assign_attributes(
        venue: data[:venue],
        city: CITY,
        ticket_url: data[:ticket_url]
      )

      screening.save!
      is_new ? :created : :updated
    end
  end
end
