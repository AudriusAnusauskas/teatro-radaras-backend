module Scrapers
  class LndtScheduleImporter
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
        Rails.logger.error("[LndtScheduleImporter] Error: #{e.message} for #{data.inspect}")
      end

      result
    end

    private

    def import_one(data)
      production = Production.find_by(source_url: data[:production_source_url])

      unless production
        Rails.logger.warn(
          "[LndtScheduleImporter] Skipping screening - production not found for " \
          "source_url=#{data[:production_source_url].inspect} " \
          "(scraper title: #{data[:production_title].inspect})"
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
        city: data[:city],
        ticket_url: data[:ticket_url]
      )

      screening.save!
      is_new ? :created : :updated
    end
  end
end
