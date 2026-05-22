class Comment < ApplicationRecord
    belongs_to :production
    belongs_to :user
  
    enum :status, {
      published: "published",
      hidden:    "hidden",
      removed:   "removed"
    }, default: :published
  
    validates :body, presence: true, length: { minimum: 3, maximum: 4_000 }
  
    scope :visible, -> { where(status: :published) }
    scope :recent,  -> { order(created_at: :desc) }
end
