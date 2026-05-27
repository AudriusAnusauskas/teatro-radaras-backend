namespace :scrapers do
  desc "Scrape 7md.lt theater reviews (default 2 pages)"
  task :import_7md, [:max_pages] => :environment do |_, args|
    max_pages = (args[:max_pages] || 2).to_i
    puts "Scraping 7md.lt teatras (#{max_pages} pages)..."

    scraper = Scrapers::SevenmdReviewScraper.new
    data = scraper.fetch_recent(category: "teatras", max_pages: max_pages)
    puts "Scraped: #{data.size}"

    result = Scrapers::SevenmdReviewImporter.new(data).import!
    puts "Result: #{result.inspect}"
  end
end
