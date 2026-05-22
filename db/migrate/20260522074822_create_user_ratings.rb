class CreateUserRatings < ActiveRecord::Migration[7.2]
  def change
    create_table :user_ratings do |t|
      t.references :production, null: false, foreign_key: true
      t.references :user,                    foreign_key: true   # nullable — anon ratings allowed

      t.integer :rating,        null: false                       # 1-5

      # Dedup keys for anonymous raters (one of these is always set)
      t.string  :session_id
      t.string  :ip_hash                                          # SHA256(ip + salt), no raw IPs

      t.timestamps
    end

    # Three uniqueness scopes — only one of user_id / session_id / ip_hash applies per row
    add_index :user_ratings, [:production_id, :user_id],
              unique: true, where: "user_id IS NOT NULL",
              name: "idx_user_ratings_user_unique"

    add_index :user_ratings, [:production_id, :session_id],
              unique: true, where: "session_id IS NOT NULL",
              name: "idx_user_ratings_session_unique"

    add_index :user_ratings, [:production_id, :ip_hash],
              unique: true, where: "ip_hash IS NOT NULL AND user_id IS NULL AND session_id IS NULL",
              name: "idx_user_ratings_ip_unique"
  end
end
