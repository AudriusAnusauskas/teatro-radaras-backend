class CreateComments < ActiveRecord::Migration[7.2]
  def change
    create_table :comments do |t|
      t.references :production, null: false, foreign_key: true
      t.references :user,       null: false, foreign_key: true

      t.text :body,             null: false

      # Moderation hooks (used later, harmless for MVP)
      t.string   :status,       null: false, default: "published"  # published|hidden|removed
      t.datetime :hidden_at

      t.timestamps
    end

    add_index :comments, [:production_id, :created_at]
    add_index :comments, :status
  end
end
