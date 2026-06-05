class AddIsGuestToProductions < ActiveRecord::Migration[7.2]
  def change
    add_column :productions, :is_guest, :boolean, null: false, default: false
    add_index :productions, :is_guest
  end
end
