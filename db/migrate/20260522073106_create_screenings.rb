class CreateScreenings < ActiveRecord::Migration[7.2]
  def change
    create_table :screenings do |t|
      t.references :production, null: false, foreign_key: true

      t.datetime :starts_at,    null: false   # combined date+time, stored as UTC, rendered in Europe/Vilnius
      t.string   :venue
      t.string   :city
      t.string   :note
      t.string   :ticket_url
      t.boolean  :is_premiere,  null: false, default: false

      t.timestamps
    end

    add_index :screenings, :starts_at
    add_index :screenings, [:production_id, :starts_at]
    add_index :screenings, :city
  end
end
