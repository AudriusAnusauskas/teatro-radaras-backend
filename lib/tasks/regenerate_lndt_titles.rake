namespace :scrapers do
  desc "Regenerate titles and slugs for LNDT productions imported via scraper"
  task regenerate_lndt_titles: :environment do
    lndt = Theater.find_by(slug: "lietuvos-nacionalinis-dramos-teatras")
    abort "LNDT theater not found" unless lndt

    productions = Production.where(theater_id: lndt.id)
                            .where("source_url LIKE ?", "%teatras.lt/lt/spektakliai%")

    total = productions.count
    puts "Found #{total} productions to (re)process"
    puts

    changed = 0
    productions.find_each do |production|
      raw_title = production.full_title.presence || production.title
      parsed = Scrapers::TitleParser.parse(raw_title)

      old_title = production.title
      old_slug = production.slug

      production.title = parsed.title
      production.author = parsed.author if parsed.author.present?
      production.based_on = parsed.based_on if parsed.based_on.present?
      production.slug = nil # Force FriendlyId to regenerate from new title.

      production.save!

      title_changed = old_title != production.title
      slug_changed = old_slug != production.slug

      if title_changed || slug_changed
        changed += 1
        puts "[#{production.id}] regenerated:"
        puts "  title: #{old_title.inspect}" if title_changed
        puts "      -> #{production.title.inspect}" if title_changed
        puts "  slug:  #{old_slug.inspect}" if slug_changed
        puts "      -> #{production.slug.inspect}" if slug_changed
        puts
      end
    end

    puts "Done. #{changed} productions changed (out of #{total} processed)."
  end
end
