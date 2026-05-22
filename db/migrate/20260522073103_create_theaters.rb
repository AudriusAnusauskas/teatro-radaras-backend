class CreateTheaters < ActiveRecord::Migration[7.2]
  def change
    create_table :theaters do |t|
      t.string  :slug,           null: false
      t.string  :name,           null: false
      t.string  :short_name
      t.string  :city,           null: false
      t.string  :address
      t.decimal :latitude,       precision: 10, scale: 7
      t.decimal :longitude,      precision: 10, scale: 7
      t.string  :phone
      t.integer :founded_year
      t.string  :current_season
      t.string  :website_url
      t.jsonb   :venues,         null: false, default: []
      t.text    :description
      t.string  :photo_url
      t.string  :photo_credit
      t.jsonb   :social,         null: false, default: {}

      t.timestamps
    end

    add_index :theaters, :slug, unique: true
    add_index :theaters, :city
  end
end
