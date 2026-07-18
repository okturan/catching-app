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

ActiveRecord::Schema[8.1].define(version: 2026_07_10_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.integer "duration", null: false
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_activities_on_event_id"
    t.check_constraint "duration > 0", name: "activities_duration_positive"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.datetime "end_time", precision: nil
    t.string "meeting_medium"
    t.string "name", null: false
    t.datetime "start_time", precision: nil
    t.boolean "status", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_events_on_user_id"
    t.check_constraint "start_time IS NULL OR end_time IS NULL OR end_time > start_time", name: "events_end_time_after_start_time"
    t.check_constraint "status = false OR start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time", name: "events_finalized_time_range"
  end

  create_table "time_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time", precision: nil
    t.bigint "event_id", null: false
    t.datetime "start_time", precision: nil, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id"], name: "index_time_slots_on_event_id"
    t.index ["user_id", "event_id", "start_time"], name: "index_time_slots_on_user_id_and_event_id_and_start_time", unique: true
    t.index ["user_id"], name: "index_time_slots_on_user_id"
  end

  create_table "user_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id"], name: "index_user_events_on_event_id"
    t.index ["user_id", "event_id"], name: "index_user_events_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_user_events_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "phone_number"
    t.datetime "remember_created_at", precision: nil
    t.datetime "reset_password_sent_at", precision: nil
    t.string "reset_password_token"
    t.string "time_zone_name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "activities", "events"
  add_foreign_key "events", "users"
  add_foreign_key "time_slots", "events"
  add_foreign_key "time_slots", "users"
  add_foreign_key "user_events", "events"
  add_foreign_key "user_events", "users"
end
