module Scrapers
  class KlaipedosCatalogImporter < BaseCatalogImporter
    THEATER_SLUG = "klaipedos-dramos-teatras"

    private

    def import_one(data)
      return [:skipped, 0] if data[:source_url].blank?

      unless data[:title].present?
        Rails.logger.warn("[KlaipedosCatalogImporter] Skipping #{data[:source_url]} — no title")
        return [:skipped, 0]
      end

      production, = find_or_initialize_production(data)
      is_new = production.new_record?
      dirs_created = 0

      if is_new
        production.theater = theater
        assign_slug(production, data[:slug], data[:title])
      end

      if is_new || production.director_id.blank?
        if data[:director].blank?
          Rails.logger.warn("[KlaipedosCatalogImporter] SKIP (no director): #{data[:slug]}")
          return [:skipped, 0]
        end

        director, dirs_created = find_or_create_director(data[:director])
        production.director = director
      end

      assign_scraped_attributes(production, data, is_new: is_new)
      production.save!

      [is_new ? :created : :updated, dirs_created]
    end

    def find_or_initialize_production(data)
      production = Production.find_by(theater_id: theater.id, source_url: data[:source_url])
      return [production, false] if production

      title_match = find_by_normalized_title(data[:title])
      return [title_match, true] if title_match

      [Production.new(theater: theater), false]
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

    def assign_scraped_attributes(production, data, is_new:)
      production.source_url = data[:source_url]

      scalar_fields = {
        title: data[:title],
        author: resolve_author(data[:author]),
        genre: data[:genre],
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        age_rating: data[:age_rating],
        description: data[:description],
        poster_url: data[:poster_url],
        translator: data[:translator],
        premiere_date: data[:premiere_date],
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
      raise "KlaipedosCatalogImporter uses assign_scraped_attributes instead"
    end
  end
end
