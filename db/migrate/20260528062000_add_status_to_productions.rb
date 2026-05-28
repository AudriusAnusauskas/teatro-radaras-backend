class AddStatusToProductions < ActiveRecord::Migration[7.2]
  def change
    add_column :productions, :status, :string, default: "active", null: false
    add_index :productions, :status
  end
end
