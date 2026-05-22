class CreateReviews < ActiveRecord::Migration[7.2]
  def change
    create_table :reviews do |t|
      t.references :production, foreign_key: true   # nullable on purpose — unmatched reviews live here too

      t.string  :author,           null: false
      t.string  :title
      t.string  :publication
      t.string  :issue
      t.date    :published_at
      t.string  :url
      t.integer :rating                              # 1-10
      t.integer :rating_max,       default: 10
      t.string  :language,         default: "lt"
      t.text    :note                                # short excerpt / anonsas (NEVER full text — copyright)

      # Matching workflow columns (Claude API job populates these)
      t.string   :match_status,    null: false, default: "pending"   # pending|matched|unmatched|manual
      t.float    :match_confidence
      t.datetime :matched_at

      t.timestamps
    end

    add_index :reviews, :publication
    add_index :reviews, :published_at
    add_index :reviews, :match_status
  end
end
