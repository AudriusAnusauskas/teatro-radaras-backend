class CreateDirectors < ActiveRecord::Migration[7.2]
  def change
    create_table :directors do |t|
      t.string  :slug,           null: false
      t.string  :name,           null: false
      t.integer :birth_year
      t.integer :death_year
      t.string  :nationality
      t.text    :bio
      t.jsonb   :notable_works,  null: false, default: []
      t.string  :photo_url
      t.string  :photo_credit
      t.string  :source_url

      t.timestamps
    end

    add_index :directors, :slug, unique: true
  end
end
