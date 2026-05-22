# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      ## Identity (Google OAuth — no password)
      t.string :email,              null: false
      t.string :name
      t.string :avatar_url

      ## OAuth (Devise omniauthable)
      t.string :provider,           null: false   # "google_oauth2"
      t.string :uid,                null: false   # Google's stable user ID

      ## Role
      t.string :role,               null: false, default: "member"   # member|moderator|admin

      ## Trackable (handy, low cost)
      t.integer  :sign_in_count,    default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, [:provider, :uid],     unique: true
  end
end
