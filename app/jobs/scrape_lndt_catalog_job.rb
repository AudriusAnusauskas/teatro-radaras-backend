class ScrapeLndtCatalogJob < ApplicationJob
  queue_as :scrapers

  def perform
    Rails.logger.info("[ScrapeLndtCatalogJob] Starting")
    data = Scrapers::LndtCatalogScraper.new.fetch_all
    result = Scrapers::LndtCatalogImporter.new(data).import!
    Rails.logger.info("[ScrapeLndtCatalogJob] Done: #{result.inspect}")
  rescue StandardError => e
    Rails.logger.error("[ScrapeLndtCatalogJob] Failed: #{e.message}")
    raise
  end
end
