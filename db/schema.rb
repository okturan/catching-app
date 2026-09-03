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

ActiveRecord::Schema[8.1].define(version: 2026_09_02_000004) do
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
    t.string "name", null: false
    t.integer "slot_minutes", default: 30, null: false
    t.datetime "start_time", precision: nil
    t.boolean "status", default: false, null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "slot_minutes = ANY (ARRAY[15, 30, 60])", name: "events_slot_minutes_allowed"
    t.check_constraint "start_time IS NULL OR end_time IS NULL OR end_time > start_time", name: "events_end_time_after_start_time"
    t.check_constraint "status = false OR (EXTRACT(epoch FROM end_time - start_time)::bigint % (slot_minutes * 60)::bigint) = 0", name: "events_finalized_window_whole_slots"
    t.check_constraint "status = false OR start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time", name: "events_finalized_time_range"
  end

  create_table "mail_deliveries", force: :cascade do |t|
    t.string "canonical_recipient_email", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "error"
    t.bigint "event_id", null: false
    t.datetime "failed_at"
    t.string "kind", null: false
    t.bigint "participant_id"
    t.string "recipient_email", null: false
    t.string "request_ip"
    t.string "sender_email"
    t.index ["canonical_recipient_email", "created_at"], name: "idx_on_canonical_recipient_email_created_at_1846ffef76"
    t.index ["event_id", "canonical_recipient_email"], name: "idx_on_event_id_canonical_recipient_email_79ed6ea4e6"
    t.index ["event_id"], name: "index_mail_deliveries_on_event_id"
    t.index ["participant_id", "created_at"], name: "index_mail_deliveries_on_participant_id_and_created_at"
    t.index ["participant_id"], name: "index_mail_deliveries_on_participant_id"
    t.index ["request_ip", "created_at"], name: "index_mail_deliveries_on_request_ip_and_created_at"
    t.index ["sender_email", "created_at"], name: "index_mail_deliveries_on_sender_email_and_created_at"
    t.check_constraint "kind::text = ANY (ARRAY['organizer_link'::character varying, 'invitation'::character varying, 'response_confirmation'::character varying, 'finalized'::character varying, 'link_shown'::character varying]::text[])", name: "mail_deliveries_kind_allowed"
  end

  create_table "participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.string "email", null: false
    t.bigint "event_id", null: false
    t.datetime "left_at"
    t.datetime "link_opened_at"
    t.string "name"
    t.string "pending_token_digest"
    t.datetime "pending_token_expires_at"
    t.datetime "responded_at"
    t.string "role", null: false
    t.string "time_zone"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["event_id", "email"], name: "index_participants_on_event_id_and_email", unique: true
    t.index ["event_id"], name: "index_participants_on_event_id"
    t.index ["event_id"], name: "index_participants_one_organizer_per_event", unique: true, where: "((role)::text = 'organizer'::text)"
    t.index ["id", "event_id"], name: "index_participants_on_id_and_event_id", unique: true
    t.index ["pending_token_digest"], name: "index_participants_on_pending_token_digest", unique: true
    t.index ["role", "email", "created_at"], name: "index_participants_on_role_and_email_and_created_at"
    t.index ["token_digest"], name: "index_participants_on_token_digest", unique: true
    t.index ["user_id", "event_id"], name: "index_participants_on_user_id_and_event_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["user_id"], name: "index_participants_on_user_id"
    t.check_constraint "declined_at IS NULL OR responded_at IS NOT NULL", name: "participants_declined_implies_responded"
    t.check_constraint "email::text = btrim(email::text) AND email::text !~ '[ABCDEFGHIJKLMNOPQRSTUVWXYZ]'::text AND POSITION(('@'::text) IN (email)) > 1", name: "participants_email_normalized"
    t.check_constraint "left_at IS NULL OR token_digest IS NULL AND pending_token_digest IS NULL AND declined_at IS NOT NULL AND user_id IS NULL AND role::text = 'guest'::text", name: "participants_left_is_revoked"
    t.check_constraint "pending_token_digest IS NULL OR char_length(pending_token_digest::text) = 64", name: "participants_pending_token_digest_length"
    t.check_constraint "pending_token_expires_at IS NULL OR pending_token_digest IS NOT NULL", name: "participants_pending_token_pair"
    t.check_constraint "role::text = ANY (ARRAY['organizer'::character varying, 'guest'::character varying]::text[])", name: "participants_role_allowed"
    t.check_constraint "token_digest IS NULL OR char_length(token_digest::text) = 64", name: "participants_token_digest_length"
  end

  create_table "time_slots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "participant_id", null: false
    t.datetime "start_time", precision: nil, null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "start_time"], name: "index_time_slots_on_event_id_and_start_time"
    t.index ["participant_id", "start_time"], name: "index_time_slots_on_participant_id_and_start_time", unique: true
    t.check_constraint "start_time = date_bin('PT15M'::interval, start_time, '2000-01-01 00:00:00'::timestamp without time zone)", name: "time_slots_start_time_quarter_hour"
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
  add_foreign_key "mail_deliveries", "events", on_delete: :cascade
  add_foreign_key "mail_deliveries", "participants", on_delete: :nullify
  add_foreign_key "participants", "events", on_delete: :cascade
  add_foreign_key "participants", "users", on_delete: :nullify
  add_foreign_key "time_slots", "events", on_delete: :cascade
  add_foreign_key "time_slots", "participants", column: ["participant_id", "event_id"], primary_key: ["id", "event_id"], name: "fk_time_slots_participant_in_event", on_delete: :cascade
end
