class ClickEvent < ApplicationRecord
    belongs_to :production
    belongs_to :screening, optional: true
    belongs_to :user,      optional: true
  
    validates :target_url, :clicked_at, presence: true
end
