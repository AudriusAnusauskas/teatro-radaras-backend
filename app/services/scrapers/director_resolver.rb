module Scrapers
  module DirectorResolver
    # Returns [director, created_count]
    def find_or_create_director(raw_name)
      name = first_director_name(raw_name)
      return [nil, 0] if name.blank?

      normalized = normalize_director_name(name)
      existing = Director.where("LOWER(name) = ?", normalized.downcase).first
      return [existing, 0] if existing

      [Director.create!(name: normalized), 1]
    end

    def normalize_director_name(name)
      cleaned = strip_director_suffix(name)
      cleaned.split(/\s+/).map { |w| w.downcase.capitalize }.join(" ")
    end

    # First director from a comma-separated string; logs when multiple.
    def first_director_name(raw)
      return nil if raw.blank?

      parts = raw.split(",").map { |p| strip_director_suffix(p).strip }.reject(&:blank?)
      if parts.size > 1
        Rails.logger.info(
          "[#{self.class.name}] Multiple directors #{raw.inspect} — using first: #{parts.first.inspect}"
        )
      end
      parts.first
    end

    # Default: no-op. VMT overrides to strip "(Country)".
    def strip_director_suffix(name)
      name.to_s.strip
    end
  end
end
