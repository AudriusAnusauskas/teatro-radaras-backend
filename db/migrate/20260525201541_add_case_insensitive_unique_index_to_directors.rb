class AddCaseInsensitiveUniqueIndexToDirectors < ActiveRecord::Migration[7.2]
  def up
    add_index :directors, "LOWER(name)", unique: true, name: "index_directors_on_lower_name"
  end

  def down
    remove_index :directors, name: "index_directors_on_lower_name"
  end
end
