module Scrapers
  class JaunimoTeatrasScheduleImporter
    THEATER_SLUG = "valstybinis-jaunimo-teatras"
    CITY = "Vilnius"

    def initialize(scraped_data)
      @scraped_data = scraped_data
    end

    def import!
      result = { created: 0, updated: 0, skipped: 0, errors: [] }

      @scraped_data.each do |data|
        outcome = import_one(data)

        case outcome
        when :created then result[:created] += 1
        when :updated then result[:updated] += 1
        when :skipped then result[:skipped] += 1
        end
      rescue StandardError => e
        result[:errors] << { data: data, error: e.message }
        Rails.logger.error("[JaunimoTeatrasScheduleImporter] Error: #{e.message} for #{data.inspect}")
      end

      result
    end

    private

    def import_one(data)
      production = find_production(data)

      unless production
        Rails.logger.warn(
          "[JaunimoTeatrasScheduleImporter] Skipping screening - production not found for " \
          "production_url=#{data[:production_url].inspect} " \
          "slug=#{data[:production_slug].inspect}"
        )
        return :skipped
      end

      unless production.theater&.slug == THEATER_SLUG
        Rails.logger.warn(
          "[JaunimoTeatrasScheduleImporter] Skipping screening - production belongs to wrong theater " \
          "(production_id=#{production.id}, theater_slug=#{production.theater&.slug.inspect}, " \
          "expected=#{THEATER_SLUG.inspect}, slug=#{data[:production_slug].inspect})"
        )
        return :skipped
      end

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

    def find_production(data)
      production = Production.find_by(source_url: data[:production_url])
      production ||= Production.find_by(slug: data[:production_slug])
      production
    end
  end
end
