class ScopeProductionSlugsToTheater < ActiveRecord::Migration[7.2]
  THEATER_SUFFIX_PATTERN = /-(okt|lndt|vmt)\z/i
  NUMERIC_SUFFIX_PATTERN = /-[0-9]+\z/

  def up
    remove_index :productions, name: "index_productions_on_slug"
    backfill_theater_scoped_slugs
    add_index :productions, %i[theater_id slug],
              unique: true,
              name: "index_productions_on_theater_id_and_slug"
  end

  def down
    remove_index :productions, name: "index_productions_on_theater_id_and_slug"
    add_index :productions, :slug, unique: true, name: "index_productions_on_slug"
  end

  private

  def backfill_theater_scoped_slugs
    used_slugs_by_theater = Hash.new { |hash, theater_id| hash[theater_id] = {} }

    Production.order(:id).find_each do |production|
      natural = natural_slug_for(production)
      candidate = disambiguate_slug(production.theater_id, natural, used_slugs_by_theater)
      used_slugs_by_theater[production.theater_id][candidate] = true

      next if production.slug == candidate

      production.update_column(:slug, candidate)
    end
  end

  def natural_slug_for(production)
    from_source = slug_from_source_url(production.source_url)
    return from_source if from_source.present?

    slug = production.slug.to_s.strip.downcase
    slug = slug.sub(NUMERIC_SUFFIX_PATTERN, "")
    slug = slug.sub(THEATER_SUFFIX_PATTERN, "")
    slug.presence || production.slug
  end

  def slug_from_source_url(source_url)
    return nil if source_url.blank?

    uri = URI.parse(source_url)
    segment = uri.path.to_s.split("/").reject(&:blank?).last.to_s
    segment = segment.sub(/\.+\z/, "").downcase
    segment.presence
  rescue URI::InvalidURIError
    nil
  end

  def disambiguate_slug(theater_id, base_slug, used_slugs_by_theater)
    candidate = base_slug
    counter = 2

    while used_slugs_by_theater[theater_id].key?(candidate)
      candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    candidate
  end
end
