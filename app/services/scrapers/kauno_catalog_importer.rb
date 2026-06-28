module Scrapers
  class KaunoCatalogImporter < BaseCatalogImporter
    THEATER_SLUG = "nacionalinis-kauno-dramos-teatras"

    private

    def import_one(data)
      return [:skipped, 0] if data[:source_url].blank?

      unless data[:title].present?
        Rails.logger.warn("[KaunoCatalogImporter] Skipping #{data[:source_url]} — no title")
        return [:skipped, 0]
      end

      production = Production.find_or_initialize_by(theater_id: theater.id, source_url: data[:source_url])
      is_new = production.new_record?
      dirs_created = 0

      if is_new
        production.theater = theater
        assign_slug(production, data[:slug], data[:title])
      end

      if is_new || production.director_id.blank?
        if data[:director].blank?
          Rails.logger.warn("[KaunoCatalogImporter] SKIP (no director): #{data[:slug]}")
          return [:skipped, 0]
        end

        director, dirs_created = find_or_create_director(data[:director])
        production.director = director
      end
      # Existing productions with director_id: do not resolve or touch director.

      assign_scraped_attributes(production, data, is_new: is_new)
      production.save!

      [is_new ? :created : :updated, dirs_created]
    end

    def assign_scraped_attributes(production, data)
      scalar_fields = {
        title: data[:title],
        full_title: data[:full_title],
        author: resolve_author(data[:author]),
        genre: data[:genre],
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        age_rating: data[:age_rating],
        description: data[:description],
        poster_url: data[:poster_url],
        translator: data[:translator],
        status: data[:status].presence || "active"
      }

      scalar_fields.each do |key, value|
        next if value.blank?

        production.public_send("#{key}=", value)
      end

      production.is_guest = true if data[:is_guest] == true

      production.cast_members = data[:cast_members] if data[:cast_members].present?
      production.creative_team = data[:creative_team] if data[:creative_team].present?

      if data[:awards].present? && (is_new || production.awards.blank?)
        production.awards = data[:awards]
      end
    end

    def production_attributes(_data, _director)
      raise "KaunoCatalogImporter uses assign_scraped_attributes instead"
    end
  end
end
