module Scrapers
  class SevenmdReviewImporter
    def initialize(scraped_reviews)
      @reviews = scraped_reviews.compact
    end

    def import!
      result = { created: 0, updated: 0, matched: 0, unmatched: 0, errors: [] }

      @reviews.each do |scraped|
        outcome = import_one(scraped)
        result[outcome[:action]] += 1
        result[outcome[:match]] += 1
      rescue StandardError => e
        result[:errors] << { url: scraped[:url], error: e.message }
        Rails.logger.error("[SevenmdReviewImporter] Error: #{e.message}")
      end

      result
    end

    private

    def import_one(scraped)
      raise ArgumentError, "author blank for #{scraped[:url].inspect}" if scraped[:author].blank?

      review = Review.find_or_initialize_by(
        publication: scraped[:publication],
        url: scraped[:url]
      )

      is_new = review.new_record?
      full_title = [scraped[:title], scraped[:subtitle]].compact.reject(&:empty?).join(" — ")

      review.assign_attributes(
        author: scraped[:author],
        title: full_title.presence || scraped[:title],
        issue: scraped[:issue],
        published_at: scraped[:published_at],
        rating: nil,
        note: scraped[:body_excerpt],
        language: "lt"
      )

      match_result = Scrapers::SevenmdReviewMatcher.new(scraped).match
      if match_result[:status] == :matched
        review.production_id = match_result[:production].id
        review.match_status = "matched"
        review.match_confidence = match_result[:confidence]
        review.matched_at = Time.current
        Rails.logger.info(
          "[SevenmdReviewImporter] Matched: #{scraped[:url]} -> " \
          "#{match_result[:production].title} (#{match_result[:signal]})"
        )
      else
        review.production_id = nil
        review.match_status = "unmatched"
        review.match_confidence = 0.0
        review.matched_at = nil
        Rails.logger.info("[SevenmdReviewImporter] Unmatched: #{scraped[:url]} (#{match_result[:signal]})")
      end

      review.save!

      {
        action: is_new ? :created : :updated,
        match: match_result[:status] == :matched ? :matched : :unmatched
      }
    end
  end
end
