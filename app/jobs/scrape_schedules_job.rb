class ScrapeSchedulesJob < ApplicationJob
  queue_as :scrapers

  def perform
    summary = {}

    Scrapers::TheaterScraperRegistry.schedule_entries.each do |entry|
      summary[entry[:key]] = scrape_schedule(entry)
    end

    Rails.logger.info("[ScrapeSchedulesJob] Summary: #{summary.inspect}")
  end

  private

  def scrape_schedule(entry)
    cfg = entry[:schedule]
    Rails.logger.info("[ScrapeSchedulesJob] #{entry[:key]} starting")
    data = cfg[:scraper].new.fetch_all
    result = cfg[:importer].new(data).import!
    Rails.logger.info("[ScrapeSchedulesJob] #{entry[:key]} done: #{result.inspect}")
    { status: :ok, result: result }
  rescue StandardError => e
    Rails.logger.error("[ScrapeSchedulesJob] #{entry[:key]} FAILED: #{e.message}")
    { status: :failed, error: e.message }
  end
end
