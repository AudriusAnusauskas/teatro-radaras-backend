module Scrapers
  class KlaipedosScheduleImporter < BaseScheduleImporter
    THEATER_SLUG = "klaipedos-dramos-teatras"
    CITY = "Klaipėda"

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
        Rails.logger.warn("[KlaipedosScheduleImporter] no production match: #{data[:source_url]}")
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

      slug = slug_from_source_url(data[:source_url])
      return nil if slug.blank?

      Production.joins(:theater)
                .where(theaters: { slug: THEATER_SLUG })
                .where("LOWER(slug) = ?", slug.downcase)
                .first
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
        ticket_url: data[:ticket_url],
        is_premiere: data[:is_premiere] == true
      )

      screening.save!
      is_new ? :created : :updated
    end

    def slug_from_source_url(source_url)
      URI.parse(source_url).path.split("/").reject(&:blank?).last
    rescue URI::InvalidURIError
      nil
    end
  end
end
