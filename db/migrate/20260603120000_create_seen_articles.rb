class CreateSeenArticles < ActiveRecord::Migration[7.2]
  def change
    create_table :seen_articles do |t|
      t.string :url, null: false
      t.string :publication, null: false
      t.string :outcome
      t.datetime :seen_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.timestamps
    end

    add_index :seen_articles, :url, unique: true
    add_index :seen_articles, [:publication, :seen_at]
  end
end
