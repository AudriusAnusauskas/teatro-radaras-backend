module Scrapers
  class JaunimoTeatrasCatalogImporter
    THEATER_SLUG = "valstybinis-jaunimo-teatras"

    def initialize(scraped_data)
      @scraped_data = scraped_data
    end

    def import!
      result = { created: 0, updated: 0, skipped: 0, directors_created: 0, errors: [] }

      @scraped_data.each do |data|
        if data[:source_url].blank?
          result[:skipped] += 1
          next
        end

        begin
          outcome, directors_created = import_one(data)
          result[outcome] += 1
          result[:directors_created] += directors_created
        rescue StandardError => e
          result[:errors] << { slug: data[:slug], source_url: data[:source_url], error: e.message }
          Rails.logger.error("[JaunimoTeatrasCatalogImporter] Failed #{data[:slug]}: #{e.message}")
        end
      end

      result
    end

    private

    def jaunimo_theater
      @jaunimo_theater ||= Theater.find_by!(slug: THEATER_SLUG)
    end

    def import_one(data)
      directors_created = 0

      director_name = first_director_name(data[:director_name])
      if director_name.blank?
        Rails.logger.warn(
          "[JaunimoTeatrasCatalogImporter] Skipping #{data[:slug]} — no director"
        )
        return [:skipped, 0]
      end

      if data[:title].blank?
        Rails.logger.warn(
          "[JaunimoTeatrasCatalogImporter] Skipping #{data[:source_url]} — no title"
        )
        return [:skipped, 0]
      end

      director, created = find_or_create_director(director_name)
      directors_created += created

      production = Production.find_or_initialize_by(source_url: data[:source_url])
      is_new = production.new_record?

      production.assign_attributes(production_attributes(data, director))

      if is_new
        production.theater = jaunimo_theater
        assign_slug(production, data[:slug], data[:title])
      end

      production.save!

      [is_new ? :created : :updated, directors_created]
    end

    def production_attributes(data, director)
      {
        title: data[:title],
        director: director,
        author: data[:author],
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

    # Directors are shared across theaters — match case-insensitively on normalized name
    # (DB has unique index on lower(name)). Returns [director, created_count].
    def find_or_create_director(name)
      normalized = normalize_director_name(name)
      existing = Director.where("LOWER(name) = ?", normalized.downcase).first
      return [existing, 0] if existing

      [Director.create!(name: normalized), 1]
    end

    def normalize_director_name(name)
      return nil if name.blank?

      name.split(/\s+/).map { |word| word.downcase.capitalize }.join(" ")
    end

    # Schema allows one director_id — take first when comma-separated, log the rest.
    def first_director_name(raw)
      return nil if raw.blank?

      parts = raw.split(",").map(&:strip).reject(&:blank?)
      if parts.size > 1
        Rails.logger.info(
          "[JaunimoTeatrasCatalogImporter] Multiple directors #{raw.inspect} — using first: #{parts.first.inspect}"
        )
      end
      parts.first
    end

    # Production slugs are globally unique (not per theater). Prefer the scraper's slug;
    # on collision, omit slug so FriendlyId generates a unique one from title on save.
    def assign_slug(production, desired_slug, title)
      candidate = desired_slug.to_s.strip
      return if candidate.blank?

      if Production.where(slug: candidate).where.not(id: production.id).exists?
        Rails.logger.warn(
          "[JaunimoTeatrasCatalogImporter] Slug collision #{candidate.inspect} for #{title.inspect} — " \
          "FriendlyId will assign from title"
        )
        production.slug = nil
        production.title = title
        return
      end

      production.slug = candidate
    end

    def parse_premiere_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
