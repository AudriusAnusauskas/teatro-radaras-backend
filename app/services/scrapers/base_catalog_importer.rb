module Scrapers
  class BaseCatalogImporter
    include Scrapers::DirectorResolver

    def initialize(scraped_data)
      @scraped_data = scraped_data || []
    end

    def import!
      results = { created: 0, updated: 0, skipped: 0, directors_created: 0, errors: [] }

      @scraped_data.each do |data|
        outcome, dirs_created = import_one(data)
        results[outcome] += 1 if %i[created updated skipped].include?(outcome)
        results[:directors_created] += dirs_created.to_i
      rescue StandardError => e
        Rails.logger.error("[#{self.class.name}] Failed #{data[:slug]}: #{e.message}")
        results[:errors] << { slug: data[:slug], source_url: data[:source_url], error: e.message }
      end

      results
    end

    private

    def import_one(data)
      return [:skipped, 0] if data[:source_url].blank?

      unless data[:title].present?
        Rails.logger.warn("[#{self.class.name}] Skipping #{data[:source_url]} — no title")
        return [:skipped, 0]
      end

      director, dirs_created = find_or_create_director(data[:director_name])
      if director.nil? && director_required?
        Rails.logger.warn("[#{self.class.name}] Skipping #{data[:slug]} — no director")
        return [:skipped, 0]
      end

      production = Production.find_or_initialize_by(source_url: data[:source_url])
      is_new = production.new_record?

      production.assign_attributes(production_attributes(data, director))

      if is_new
        production.theater = theater
        assign_slug(production, data[:slug], data[:title])
      end

      production.save!
      [is_new ? :created : :updated, dirs_created]
    end

    def theater
      @theater ||= Theater.find_by!(slug: self.class::THEATER_SLUG)
    end

    def assign_slug(production, desired_slug, title)
      candidate = desired_slug.to_s.strip.downcase

      if candidate.blank? || Production.where("LOWER(slug) = ?", candidate).where.not(id: production.id).exists?
        production.slug = nil
        production.title = title
      else
        production.slug = candidate
      end
    end

    def parse_premiere_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end

    def director_required? = true
    def production_attributes(data, director) = raise NotImplementedError
  end
end
