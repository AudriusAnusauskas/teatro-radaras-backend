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

    enum :status, { active: "active", archived: "archived" }, default: "active", validate: true
  
    validates :slug, :title, presence: true
    validates :slug, uniqueness: true
  
    scope :by_city,        ->(city)  { joins(:theater).where(theaters: { city: city }) }
    scope :by_genre,       ->(genre) { where(genre: genre) }
    scope :upcoming_first, -> { left_joins(:screenings).where("screenings.starts_at >= ?", Time.current).distinct.order("MIN(screenings.starts_at)").group(:id) }
  
    # Score helpers — single source of truth, used by API serializers and admin.
    # critic_score: 1-5 scale — average radaras_score from AI-classified reviews.
    # Computed in Ruby over the (eager-loaded) reviews association to avoid N+1.
    def critic_score
      scored = reviews.select { |r| r.radaras_score.present? }
      return nil if scored.empty?

      (scored.sum(&:radaras_score) / scored.size).round(1)
    end

    # critic_review_count: number of reviews carrying a radaras_score
    def critic_review_count
      reviews.count { |r| r.radaras_score.present? }
    end

    # audience_score: 1-5 scale
    def audience_score
      user_ratings.average(:rating)&.to_f&.round(2)
    end
  
    def audience_count
      user_ratings.count
    end
end
