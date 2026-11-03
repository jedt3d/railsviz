class CreateVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :visits do |t|
      t.references :patient, null: false, foreign_key: true
      t.datetime :seen_at

      t.timestamps
    end
  end
end
