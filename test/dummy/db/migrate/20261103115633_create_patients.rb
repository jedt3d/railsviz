class CreatePatients < ActiveRecord::Migration[8.1]
  def change
    create_table :patients do |t|
      t.string :name, null: false
      t.date :born_on

      t.timestamps
    end
    add_index :patients, :name
  end
end
