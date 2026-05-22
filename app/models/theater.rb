class Theater < ApplicationRecord
    extend FriendlyId
    friendly_id :name, use: :slugged
  
    has_many :productions, dependent: :destroy
  
    validates :slug, :name, :city, presence: true
    validates :slug, uniqueness: true
  
    scope :by_city, ->(city) { where(city: city) }
  end
