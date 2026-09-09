class CreateVenues < ActiveRecord::Migration[8.1]
  def change
    create_table :venues do |t|
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :address
      t.integer :capacity

      t.timestamps
    end

    add_index :venues, :external_id, unique: true
  end
end
