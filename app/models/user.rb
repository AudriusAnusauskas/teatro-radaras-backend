class User < ApplicationRecord
  devise :omniauthable, :trackable, omniauth_providers: [:google_oauth2]

  enum :role, { member: "member", moderator: "moderator", admin: "admin" }, default: "member"

  validates :email,    presence: true, uniqueness: true
  validates :provider, presence: true
  validates :uid,      presence: true, uniqueness: { scope: :provider }

  def self.from_google_omniauth(auth)
    find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
      user.email      = auth.info.email
      user.name       = auth.info.name
      user.avatar_url = auth.info.image
      user.save!
    end
  end
end
