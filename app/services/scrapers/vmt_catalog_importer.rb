module Scrapers
  class VmtCatalogImporter
    THEATER_SLUG = "valstybinis-vilniaus-mazasis-teatras"
    DIRECTOR_COUNTRY_SUFFIX_PATTERN = /\s*\([^)]+\)\z/

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
          Rails.logger.error("[VmtCatalogImporter] Failed #{data[:slug]}: #{e.message}")
        end
      end

      result
    end

    private

    def vmt_theater
      @vmt_theater ||= Theater.find_by!(slug: THEATER_SLUG)
    end

    def import_one(data)
      directors_created = 0

      director_name = first_director_name(data[:director_name])
      if director_name.blank?
        Rails.logger.warn("[VmtCatalogImporter] Skipping #{data[:slug]} — no director")
        return [:skipped, 0]
      end

      if data[:title].blank?
        Rails.logger.warn("[VmtCatalogImporter] Skipping #{data[:source_url]} — no title")
        return [:skipped, 0]
      end

      director, created = find_or_create_director(director_name)
      directors_created += created

      production = Production.find_or_initialize_by(source_url: data[:source_url])
      is_new = production.new_record?

      production.assign_attributes(production_attributes(data, director))

      if is_new
        production.theater = vmt_theater
        assign_slug(production, data[:slug], data[:title])
      end

      production.save!

      [is_new ? :created : :updated, directors_created]
    end

    def production_attributes(data, director)
      genre, creative_team = resolve_genre_and_creative_team(data)

      {
        title: data[:title],
        director: director,
        author: data[:author],
        translator: data[:translator],
        genre: genre,
        age_rating: data[:age_rating],
        premiere_date: parse_premiere_date(data[:premiere_date]),
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        description: data[:description],
        cast_members: data[:cast] || [],
        creative_team: creative_team,
        poster_url: data[:poster_url],
        is_guest: data[:is_guest] == true,
        status: "active"
      }
    end

    def resolve_genre_and_creative_team(data)
      creative_team = (data[:creative_team] || {}).stringify_keys.dup
      genre = data[:genre]

      if data[:is_guest] && guest_theater_name?(genre)
        creative_team["Svečių teatras"] = genre
        genre = nil
      end

      [genre, creative_team]
    end

    def guest_theater_name?(genre)
      return false if genre.blank?

      genre.match?(/\ATeatras\b/i) || genre.include?("„") || genre.include?('"')
    end

    def find_or_create_director(name)
      normalized = normalize_director_name(name)
      existing = Director.where("LOWER(name) = ?", normalized.downcase).first
      return [existing, 0] if existing

      [Director.create!(name: normalized), 1]
    end

    def normalize_director_name(name)
      return nil if name.blank?

      cleaned = strip_country_suffix(name)
      cleaned.split(/\s+/).map { |word| word.downcase.capitalize }.join(" ")
    end

    def strip_country_suffix(name)
      name.gsub(DIRECTOR_COUNTRY_SUFFIX_PATTERN, "").strip
    end

    def first_director_name(raw)
      return nil if raw.blank?

      parts = raw.split(",").map { |part| strip_country_suffix(part) }.map(&:strip).reject(&:blank?)
      if parts.size > 1
        Rails.logger.info(
          "[VmtCatalogImporter] Multiple directors #{raw.inspect} — using first: #{parts.first.inspect}"
        )
      end
      parts.first
    end

    def assign_slug(production, desired_slug, title)
      candidate = desired_slug.to_s.strip.downcase
      return if candidate.blank?

      if Production.where("LOWER(slug) = ?", candidate).where.not(id: production.id).exists?
        Rails.logger.warn(
          "[VmtCatalogImporter] Slug collision #{candidate.inspect} for #{title.inspect} — " \
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
