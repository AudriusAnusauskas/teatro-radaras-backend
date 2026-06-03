module Scrapers
  class ImportReviewsForProduction
    PUBLICATION = "7 meno dienos"
    REQUEST_DELAY = 4.0 # seconds between Claude/scrape calls — stays under tier 1 limit (50K tokens/min)

    def initialize(production)
      @production = production
      @tag_scraper = SevenmdProductionTagScraper.new
      @article_scraper = SevenmdReviewScraper.new
      @classifier = ReviewClassifier.new
    end

    # Returns counts hash
    def call
      result = { fetched: 0, classified: 0, imported: 0, skipped_not_review: 0, skipped_dedup: 0, errors: [] }

      urls = @tag_scraper.fetch_article_urls(@production.title)
      Rails.logger.info("[ImportReviewsForProduction] #{@production.title}: #{urls.size} candidate URLs")
      result[:fetched] = urls.size

      urls.each do |url|
        # Primary dedup: already processed this URL (any outcome) — skip the Claude call.
        if SeenArticle.exists?(url: url)
          result[:skipped_dedup] += 1
          next
        end

        # Secondary safety: review with this URL already imported (idempotency).
        if Review.exists?(publication: PUBLICATION, url: url)
          result[:skipped_dedup] += 1
          next
        end

        article = @article_scraper.fetch_article_full(url)
        next unless article && article[:body].present?

        sleep(REQUEST_DELAY)

        classification = @classifier.classify(
          article_title: article[:title].to_s,
          article_body: article[:body],
          production_title: @production.title
        )
        result[:classified] += 1
        sleep(REQUEST_DELAY)

        if classification[:is_review]
          Review.create!(
            production: @production,
            publication: PUBLICATION,
            url: url,
            title: article[:title],
            author: article[:author].presence || "Nežinomas",
            issue: article[:issue],
            published_at: article[:published_at],
            note: classification[:quote] || article[:body_excerpt],
            radaras_score: classification[:radaras_score],
            match_status: "matched",
            match_confidence: 1.0,
            matched_at: Time.current,
            language: "lt"
          )
          result[:imported] += 1
          record_seen(url, "imported")
          Rails.logger.info("[ImportReviewsForProduction] ✓ Imported: #{article[:title]} (score #{classification[:radaras_score]})")
        else
          result[:skipped_not_review] += 1
          record_seen(url, "not_review")
          Rails.logger.info("[ImportReviewsForProduction] ✗ Not a review: #{article[:title]}")
        end
      rescue ClaudeClient::RateLimitError => e
        # Rate-limited: transient — do NOT cache, so the article retries next run.
        result[:errors] << { url: url, error: "rate_limited: #{e.message}" }
        Rails.logger.warn("[ImportReviewsForProduction] Rate limited on #{url}: #{e.message}")
      rescue StandardError => e
        # Other errors are also left uncached so they can be retried.
        result[:errors] << { url: url, error: e.message }
        Rails.logger.error("[ImportReviewsForProduction] Error #{url}: #{e.message}")
      end

      result
    end

    private

    def record_seen(url, outcome)
      SeenArticle.create!(url: url, publication: PUBLICATION, outcome: outcome, seen_at: Time.current)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Already recorded (re-run / race) — safe to ignore.
    end
  end
end
