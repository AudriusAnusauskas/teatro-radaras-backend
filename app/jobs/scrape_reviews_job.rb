class ScrapeReviewsJob < ApplicationJob
  queue_as :scrapers

  # Weekly review scrape across both sources (7md.lt + menufaktura.lt).
  # Each importer dedups via SeenArticle, so only unseen articles hit Claude.
  def perform
    results = { sevenmd: zero_counts, menufaktura: zero_counts }

    Production.active.find_each do |production|
      merge_counts!(results[:sevenmd], run_sevenmd(production))
      merge_counts!(results[:menufaktura], run_menufaktura(production))
    end

    Rails.logger.info("[ScrapeReviewsJob] Done: #{results.inspect}")
    results
  end

  private

  def run_sevenmd(production)
    Scrapers::ImportReviewsForProduction.new(production).call
  rescue StandardError => e
    Rails.logger.error("[ScrapeReviewsJob] 7md failed for #{production.title}: #{e.message}")
    zero_counts.merge(errors: [{ production: production.title, error: e.message }])
  end

  def run_menufaktura(production)
    Scrapers::ImportMenufakturaReviewsForProduction.new(production).call
  rescue StandardError => e
    Rails.logger.error("[ScrapeReviewsJob] menufaktura failed for #{production.title}: #{e.message}")
    zero_counts.merge(errors: [{ production: production.title, error: e.message }])
  end

  def merge_counts!(acc, result)
    acc.merge!(result) { |_key, a, b| a + b }
  end

  def zero_counts
    { fetched: 0, classified: 0, imported: 0,
      skipped_not_review: 0, skipped_dedup: 0, errors: [] }
  end
end
