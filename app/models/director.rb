class Director < ApplicationRecord
    extend FriendlyId
    friendly_id :name, use: :slugged
  
    has_many :productions, dependent: :restrict_with_error
  
    validates :slug, :name, presence: true
    validates :slug, uniqueness: true
end
