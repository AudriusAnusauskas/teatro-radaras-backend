class SeenArticle < ApplicationRecord
  # Tracks every article URL we've processed (regardless of classification
  # outcome) so re-runs don't re-spend Claude tokens re-classifying the same
  # non-reviews. Distinct from Review, which only holds imported reviews.
  OUTCOMES = %w[imported not_review error].freeze

  validates :url, presence: true, uniqueness: true
  validates :publication, presence: true
end
