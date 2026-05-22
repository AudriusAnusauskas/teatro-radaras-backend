class Screening < ApplicationRecord
    belongs_to :production
  
    validates :starts_at, presence: true
  
    scope :upcoming,     -> { where("starts_at >= ?", Time.current).order(:starts_at) }
    scope :past,         -> { where("starts_at < ?", Time.current).order(starts_at: :desc) }
    scope :this_week,    -> { where(starts_at: Time.current.beginning_of_day..1.week.from_now) }
    scope :in_city,      ->(city) { where(city: city) }
end
