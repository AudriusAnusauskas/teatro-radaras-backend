class Production < ApplicationRecord
    extend FriendlyId
    friendly_id :title, use: :slugged
  
    belongs_to :theater
    belongs_to :director
  
    has_many :screenings,   dependent: :destroy
    has_many :reviews,      dependent: :nullify    # recenzija autonomiška (gali likti archyvinė)
    has_many :user_ratings, dependent: :destroy
    has_many :comments,     dependent: :destroy
    has_many :click_events, dependent: :nullify    # analytics archyvas
  
    validates :slug, :title, presence: true
    validates :slug, uniqueness: true
  
    scope :by_city,        ->(city)  { joins(:theater).where(theaters: { city: city }) }
    scope :by_genre,       ->(genre) { where(genre: genre) }
    scope :upcoming_first, -> { left_joins(:screenings).where("screenings.starts_at >= ?", Time.current).distinct.order("MIN(screenings.starts_at)").group(:id) }
  
    # Score helpers — single source of truth, used by API serializers and admin.
    # critic_score: 1-10 scale (matched reviews only)
    def critic_score
      reviews.matched.where.not(rating: nil).average(:rating)&.to_f&.round(1)
    end
  
    # audience_score: 1-5 scale
    def audience_score
      user_ratings.average(:rating)&.to_f&.round(2)
    end
  
    def audience_count
      user_ratings.count
    end
end
