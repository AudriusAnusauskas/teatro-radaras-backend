class ScrapeLndtScheduleJob < ApplicationJob
  queue_as :scrapers

  def perform
    Rails.logger.info("[ScrapeLndtScheduleJob] Starting")
    data = Scrapers::LndtScheduleScraper.new.fetch_all
    result = Scrapers::LndtScheduleImporter.new(data).import!
    Rails.logger.info("[ScrapeLndtScheduleJob] Done: #{result.inspect}")
  rescue StandardError => e
    Rails.logger.error("[ScrapeLndtScheduleJob] Failed: #{e.message}")
    raise
  end
end
