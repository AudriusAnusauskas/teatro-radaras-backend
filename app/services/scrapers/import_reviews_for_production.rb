module Scrapers
  class ImportReviewsForProduction
    PUBLICATION = "7 meno dienos"
    REQUEST_DELAY = 1.0 # seconds between Claude/scrape calls

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
        # Dedup: skip if review with this URL+publication already in DB
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
          Rails.logger.info("[ImportReviewsForProduction] ✓ Imported: #{article[:title]} (score #{classification[:radaras_score]})")
        else
          result[:skipped_not_review] += 1
          Rails.logger.info("[ImportReviewsForProduction] ✗ Not a review: #{article[:title]}")
        end
      rescue StandardError => e
        result[:errors] << { url: url, error: e.message }
        Rails.logger.error("[ImportReviewsForProduction] Error #{url}: #{e.message}")
      end

      result
    end
  end
end
