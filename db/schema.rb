# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_31_120003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "films", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.integer "runtime"
    t.text "synopsis"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["external_id"], name: "index_films_on_external_id", unique: true
  end

  create_table "screenings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.bigint "film_id", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.bigint "venue_id", null: false
    t.index ["external_id"], name: "index_screenings_on_external_id", unique: true
    t.index ["film_id"], name: "index_screenings_on_film_id"
    t.index ["starts_at"], name: "index_screenings_on_starts_at"
    t.index ["venue_id"], name: "index_screenings_on_venue_id"
  end

  create_table "venues", force: :cascade do |t|
    t.string "address"
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_venues_on_external_id", unique: true
  end

  add_foreign_key "screenings", "films"
  add_foreign_key "screenings", "venues"
end
