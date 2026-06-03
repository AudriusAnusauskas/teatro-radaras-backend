module Scrapers
  class ImportMenufakturaReviewsForProduction
    PUBLICATION = "menufaktura.lt"
    REQUEST_DELAY = 3.0 # seconds between Claude API calls

    def initialize(production, matcher: nil)
      @production = production
      @matcher = matcher || MenufakturaProductionMatcher.new
      @classifier = ReviewClassifier.new
    end

    # Returns counts hash
    def call
      result = { fetched: 0, classified: 0, imported: 0, skipped_not_review: 0, skipped_dedup: 0, errors: [] }

      menufaktura_id = @matcher.find_id(@production)
      unless menufaktura_id
        Rails.logger.info("[ImportMenufakturaReviews] No menufaktura.lt match for #{@production.title}")
        return result
      end

      reviews = MenufakturaReviewScraper.new(menufaktura_id).fetch_all
      Rails.logger.info("[ImportMenufakturaReviews] #{@production.title} (id #{menufaktura_id}): #{reviews.size} reviews")
      result[:fetched] = reviews.size

      reviews.each do |review|
        if Review.exists?(publication: PUBLICATION, url: review[:url])
          result[:skipped_dedup] += 1
          next
        end

        body = review[:body].presence || review[:quote].to_s
        next if body.blank?

        classification = @classifier.classify(
          article_title: review[:title].to_s,
          article_body: body,
          production_title: @production.title
        )
        result[:classified] += 1
        sleep(REQUEST_DELAY)

        if classification[:is_review]
          Review.create!(
            production: @production,
            publication: PUBLICATION,
            url: review[:url],
            title: review[:title],
            author: review[:author].presence || "Nežinomas",
            published_at: review[:published_on],
            note: classification[:quote] || review[:quote],
            radaras_score: classification[:radaras_score],
            match_status: "matched",
            match_confidence: 1.0,
            matched_at: Time.current,
            language: "lt"
          )
          result[:imported] += 1
          Rails.logger.info("[ImportMenufakturaReviews] ✓ Imported: #{review[:title]} (score #{classification[:radaras_score]})")
        else
          result[:skipped_not_review] += 1
          Rails.logger.info("[ImportMenufakturaReviews] ✗ Not a review: #{review[:title]}")
        end
      rescue ClaudeClient::RateLimitError => e
        result[:errors] << { url: review[:url], error: "rate_limited: #{e.message}" }
        Rails.logger.warn("[ImportMenufakturaReviews] Rate limited on #{review[:url]}: #{e.message}")
      rescue StandardError => e
        result[:errors] << { url: review[:url], error: e.message }
        Rails.logger.error("[ImportMenufakturaReviews] Error #{review[:url]}: #{e.message}")
      end

      result
    end
  end
end
