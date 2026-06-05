class ScrapeCatalogsJob < ApplicationJob
  queue_as :scrapers

  def perform
    summary = {}

    Scrapers::TheaterScraperRegistry.catalog_entries.each do |entry|
      summary[entry[:key]] = scrape_catalog(entry)
    end

    Rails.logger.info("[ScrapeCatalogsJob] Summary: #{summary.inspect}")
  end

  private

  def scrape_catalog(entry)
    cfg = entry[:catalog]
    Rails.logger.info("[ScrapeCatalogsJob] #{entry[:key]} starting")
    data = cfg[:scraper].new.fetch_all
    result = cfg[:importer].new(data).import!
    Rails.logger.info("[ScrapeCatalogsJob] #{entry[:key]} done: #{result.inspect}")
    { status: :ok, result: result }
  rescue StandardError => e
    Rails.logger.error("[ScrapeCatalogsJob] #{entry[:key]} FAILED: #{e.message}")
    { status: :failed, error: e.message }
  end
end
