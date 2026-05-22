class UserRating < ApplicationRecord
    belongs_to :production
    belongs_to :user, optional: true
  
    validates :rating, presence: true, numericality: { only_integer: true, in: 1..5 }
    validate  :identifier_present
  
    scope :for_production, ->(prod) { where(production_id: prod.id) }
  
    private
  
    # Exactly one identification axis must be present, in priority order:
    # logged-in user > session cookie > IP hash fallback.
    def identifier_present
      return if user_id.present? || session_id.present? || ip_hash.present?
  
      errors.add(:base, "must have user_id, session_id, or ip_hash")
    end
end
