module Scrapers
  class LndtCatalogImporter
    LNDT_THEATER_SLUG = "lietuvos-nacionalinis-dramos-teatras"

    def initialize(productions_data)
      @productions_data = productions_data
    end

    def import!
      result = { created: 0, updated: 0, errors: [] }

      @productions_data.each do |data|
        next if data[:source_url].blank?

        begin
          outcome = import_one(data)
          result[outcome] += 1
        rescue StandardError => e
          result[:errors] << { slug: data[:slug], error: e.message }
          Rails.logger.error("[LndtCatalogImporter] Failed #{data[:slug]}: #{e.message}")
        end
      end

      result
    end

    private

    def lndt_theater
      @lndt_theater ||= Theater.find_by!(slug: LNDT_THEATER_SLUG)
    end

    def import_one(data)
      director = find_or_create_director(name: data[:director_name], source_url: data[:director_url])
      raw_title = data[:full_title].presence || data[:title]
      parsed = Scrapers::TitleParser.parse(raw_title)
      production = Production.find_or_initialize_by(source_url: data[:source_url])
      is_new = production.new_record?

      production.assign_attributes(mutable_attributes(data))

      if is_new
        production.theater = lndt_theater
        production.director = director
        production.title = parsed.title
        production.full_title = raw_title
        production.author = parsed.author
        production.based_on = parsed.based_on
      else
        production.full_title = raw_title if raw_title.present?

        if production.director_id != director&.id && director.present?
          Rails.logger.warn(
            "[LndtCatalogImporter] Director mismatch for #{production.slug}: " \
            "DB has #{production.director&.name.inspect}, scraper has #{director.name.inspect}. " \
            "Keeping DB value."
          )
        end
      end

      production.save!

      is_new ? :created : :updated
    end

    def find_or_create_director(name:, source_url: nil)
      return nil if name.blank?

      normalized = normalize_director_name(name)
      Director.find_by(name: normalized) || Director.create!(name: normalized, source_url: source_url)
    end

    def normalize_director_name(name)
      return nil if name.blank?

      name.split(/\s+/).map { |word| word.downcase.capitalize }.join(" ")
    end

    def mutable_attributes(data)
      {
        description: data[:description],
        runtime: data[:runtime],
        runtime_minutes: data[:runtime_minutes],
        age_rating: data[:age_rating],
        poster_url: data[:poster_url],
        cast_members: data[:cast] || [],
        creative_team: data[:creative_team] || {},
        premiere_date: data[:premiere_date]
      }.compact
    end
  end
end
