class CreateProductions < ActiveRecord::Migration[7.2]
  def change
    create_table :productions do |t|
      t.references :theater,  null: false, foreign_key: true
      t.references :director, null: false, foreign_key: true

      t.string  :slug,            null: false
      t.string  :title,           null: false
      t.string  :full_title
      t.string  :author
      t.string  :translator
      t.string  :based_on
      t.string  :genre
      t.date    :premiere_date
      t.string  :runtime              # human-readable "1 val. 40 min."
      t.integer :runtime_minutes
      t.string  :age_rating
      t.string  :age_note
      t.string  :venue
      t.string  :language,        default: "lt"
      t.text    :description
      t.text    :director_quote
      t.string  :poster_url
      t.string  :video_url
      t.string  :source_url
      t.jsonb   :awards,          null: false, default: []
      t.jsonb   :creative_team,   null: false, default: {}
      t.jsonb   :cast_members,    null: false, default: []   # `cast` is a name we avoid — conflicts with AR typecasting
      t.integer :ensemble_size

      t.timestamps
    end

    add_index :productions, :slug, unique: true
    add_index :productions, :genre
    add_index :productions, :premiere_date
  end
end
