class CreateClickEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :click_events do |t|
      t.references :production, null: false, foreign_key: true
      t.references :screening,                foreign_key: true   # nullable — click might not be tied to a showing
      t.references :user,                     foreign_key: true   # nullable — anon clicks dominate

      t.string :target_url,    null: false                         # the outbound URL (bilietai.lt etc.)
      t.string :ip_hash                                            # SHA256(ip + salt)
      t.string :user_agent
      t.string :referrer

      t.datetime :clicked_at,  null: false
    end

    add_index :click_events, :clicked_at
    add_index :click_events, [:production_id, :clicked_at]
  end
end
