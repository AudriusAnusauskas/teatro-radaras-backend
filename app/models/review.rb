class Review < ApplicationRecord
    belongs_to :production, optional: true   # unmatched reviews exist before AI assigns them
  
    enum :match_status, {
      pending:   "pending",
      matched:   "matched",
      unmatched: "unmatched",
      manual:    "manual"
    }, default: :pending
  
    validates :author, presence: true
    validates :rating, numericality: { in: 1..10 }, allow_nil: true
  
    scope :recent,      -> { order(published_at: :desc) }
    scope :by_year,     ->(year) { where("EXTRACT(YEAR FROM published_at) = ?", year) }
end
