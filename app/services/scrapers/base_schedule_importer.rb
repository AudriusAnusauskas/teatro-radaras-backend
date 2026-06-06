module Scrapers
  class BaseScheduleImporter
    CITY = "Vilnius"

    def initialize(scraped_data)
      @scraped_data = scraped_data || []
    end

    def import!
      results = { created: 0, updated: 0, skipped: 0, errors: [] }

      @scraped_data.each do |data|
        outcome = import_one(data)
        results[outcome] += 1 if %i[created updated skipped].include?(outcome)
      rescue StandardError => e
        Rails.logger.error("[#{self.class.name}] Failed: #{e.message}")
        results[:errors] << { data: data, error: e.message }
      end

      results
    end

    private

    def import_one(data)
      production = find_production(data)
      return skip("production not found", data) unless production

      if theater_slug && production.theater&.slug != theater_slug
        return skip("wrong theater (#{production.theater&.slug})", data)
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
        venue: data[:venue],
        city: city_for(data),
        ticket_url: data[:ticket_url]
      )

      screening.save!
      is_new ? :created : :updated
    end

    def find_production(data)
      production = Production.find_by(source_url: data[url_key])
      if production.nil? && slug_key && data[slug_key].present?
        rel = Production.where("LOWER(slug) = ?", data[slug_key].to_s.downcase)
        rel = rel.joins(:theater).where(theaters: { slug: theater_slug }) if theater_slug
        production = rel.first
      end
      production
    end

    def skip(reason, data)
      Rails.logger.warn(
        "[#{self.class.name}] Skipping screening - #{reason} for #{data.slice(url_key, slug_key).inspect}"
      )
      :skipped
    end

    def theater_slug = nil
    def url_key = :production_url
    def slug_key = :production_slug
    def city_for(_data) = CITY
  end
end
