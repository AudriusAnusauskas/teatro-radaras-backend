namespace :scrapers do
  desc "Merge duplicate directors with case-mismatched names (LT/PL diacritics)"
  task cleanup_lndt_directors: :environment do
    by_lower = Director.all.group_by { |director| director.name.downcase }

    by_lower.each_value do |directors|
      next if directors.size < 2

      canonical = directors.find do |director|
        director.name.split.all? { |word| word[0] == word[0].upcase }
      end || directors.first

      duplicates = directors - [canonical]

      duplicates.each do |duplicate|
        moved_count = duplicate.productions.count
        duplicate.productions.update_all(director_id: canonical.id)

        puts "Merged #{duplicate.name} (#{duplicate.id}) -> #{canonical.name} (#{canonical.id})"
        puts "  Moved #{moved_count} productions"

        duplicate.destroy!
      end
    end

    puts "Cleanup complete. Total directors: #{Director.count}"
  end
end
