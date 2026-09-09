class CreateScreenings < ActiveRecord::Migration[8.1]
  def change
    create_table :screenings do |t|
      t.string :external_id, null: false
      t.references :film, null: false, foreign_key: true
      t.references :venue, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.string :status, null: false, default: "scheduled"

      t.timestamps
    end

    add_index :screenings, :external_id, unique: true
    add_index :screenings, :starts_at
  end
end
