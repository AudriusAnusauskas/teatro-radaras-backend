class AddRadarasScoreToReviews < ActiveRecord::Migration[7.2]
  def change
    add_column :reviews, :radaras_score, :float
    add_index :reviews, :radaras_score
  end
end
