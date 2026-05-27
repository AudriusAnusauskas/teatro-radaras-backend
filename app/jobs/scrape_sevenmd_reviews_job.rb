class ScrapeSevenmdReviewsJob
  include Sidekiq::Job

  sidekiq_options queue: :scrapers, retry: 3

  def perform(max_pages: 2)
    Rails.logger.info("[ScrapeSevenmdReviewsJob] Starting 7md.lt reviews scrape, max_pages: #{max_pages}")

    scraper = Scrapers::SevenmdReviewScraper.new
    data = scraper.fetch_recent(category: "teatras", max_pages: max_pages)
    Rails.logger.info("[ScrapeSevenmdReviewsJob] Scraped #{data.size} articles")

    result = Scrapers::SevenmdReviewImporter.new(data).import!
    Rails.logger.info("[ScrapeSevenmdReviewsJob] Imported: #{result.inspect}")

    result
  end
end
