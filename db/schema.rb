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

ActiveRecord::Schema[8.1].define(version: 2026_10_05_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "events", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.integer "duration_minutes"
    t.datetime "end_time", precision: nil
    t.string "name", null: false
    t.integer "notified_revision", default: 0, null: false
    t.datetime "offer_revised_at"
    t.integer "offer_revision_added", default: 0, null: false
    t.integer "offer_revision_removed", default: 0, null: false
    t.string "place"
    t.string "place_url"
    t.integer "reopen_count", default: 0, null: false
    t.datetime "reopened_at"
    t.integer "revision", default: 0, null: false
    t.integer "slot_minutes", default: 30, null: false
    t.datetime "start_time", precision: nil
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "(start_time IS NULL) = (end_time IS NULL)", name: "events_window_complete"
    t.check_constraint "duration_minutes IS NULL OR duration_minutes > 0 AND (duration_minutes % 15) = 0", name: "events_duration_minutes_whole_quarters"
    t.check_constraint "notified_revision >= 0 AND notified_revision <= revision", name: "events_revisions_ordered"
    t.check_constraint "offer_revised_at IS NULL AND offer_revision_added = 0 AND offer_revision_removed = 0 OR offer_revised_at IS NOT NULL AND (offer_revision_added + offer_revision_removed) > 0", name: "events_offer_revision_counts"
    t.check_constraint "place_url IS NULL OR place_url::text ~ '^[Hh][Tt][Tt][Pp][Ss]?://'::text", name: "events_place_url_scheme"
    t.check_constraint "slot_minutes = ANY (ARRAY[15, 30, 60])", name: "events_slot_minutes_allowed"
    t.check_constraint "start_time IS NULL OR (EXTRACT(epoch FROM end_time - start_time)::bigint % (slot_minutes * 60)::bigint) = 0", name: "events_window_whole_slots"
    t.check_constraint "start_time IS NULL OR end_time IS NULL OR end_time > start_time", name: "events_end_time_after_start_time"
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
    t.index ["canonical_recipient_email", "created_at"], name: "index_mail_deliveries_on_recipient_and_created_at"
    t.index ["event_id", "canonical_recipient_email"], name: "index_mail_deliveries_on_event_and_recipient"
    t.index ["participant_id", "created_at"], name: "index_mail_deliveries_on_participant_id_and_created_at"
    t.index ["request_ip", "created_at"], name: "index_mail_deliveries_on_request_ip_and_created_at"
    t.index ["sender_email", "created_at"], name: "index_mail_deliveries_on_sender_email_and_created_at"
    t.check_constraint "kind::text = ANY (ARRAY['organizer_link'::character varying, 'invitation'::character varying, 'response_confirmation'::character varying, 'finalized'::character varying, 'link_shown'::character varying, 'event_updated'::character varying, 'cancelled'::character varying, 'reopened'::character varying]::text[])", name: "mail_deliveries_kind_allowed"
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
    t.datetime "reply_voided_at"
    t.datetime "responded_at"
    t.string "role", null: false
    t.string "time_zone"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["event_id", "email"], name: "index_participants_on_event_id_and_email", unique: true
    t.index ["event_id"], name: "index_participants_one_organizer_per_event", unique: true, where: "((role)::text = 'organizer'::text)"
    t.index ["id", "event_id"], name: "index_participants_on_id_and_event_id", unique: true
    t.index ["pending_token_digest"], name: "index_participants_on_pending_token_digest", unique: true
    t.index ["role", "email", "created_at"], name: "index_participants_on_role_and_email_and_created_at"
    t.index ["token_digest"], name: "index_participants_on_token_digest", unique: true
    t.index ["user_id", "event_id"], name: "index_participants_on_user_id_and_event_id", unique: true, where: "(user_id IS NOT NULL)"
    t.check_constraint "declined_at IS NULL OR responded_at IS NOT NULL", name: "participants_declined_implies_responded"
    t.check_constraint "email::text = btrim(email::text) AND email::text !~ '[ABCDEFGHIJKLMNOPQRSTUVWXYZ]'::text AND POSITION(('@'::text) IN (email)) > 1", name: "participants_email_normalized"
    t.check_constraint "left_at IS NULL OR token_digest IS NULL AND pending_token_digest IS NULL AND declined_at IS NOT NULL AND user_id IS NULL AND role::text = 'guest'::text", name: "participants_left_is_revoked"
    t.check_constraint "pending_token_digest IS NULL OR char_length(pending_token_digest::text) = 64", name: "participants_pending_token_digest_length"
    t.check_constraint "pending_token_expires_at IS NULL OR pending_token_digest IS NOT NULL", name: "participants_pending_token_pair"
    t.check_constraint "reply_voided_at IS NULL OR responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL AND role::text = 'guest'::text", name: "participants_voided_is_open_reply"
    t.check_constraint "role::text = ANY (ARRAY['organizer'::character varying, 'guest'::character varying]::text[])", name: "participants_role_allowed"
    t.check_constraint "token_digest IS NULL OR char_length(token_digest::text) = 64", name: "participants_token_digest_length"
  end

  create_table "plan_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_minutes"
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "position"], name: "index_plan_items_on_event_id_and_position"
    t.check_constraint "\"position\" >= 0", name: "plan_items_position_non_negative"
    t.check_constraint "duration_minutes IS NULL OR duration_minutes > 0", name: "plan_items_duration_positive"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "email_confirmed_at"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "login_link_used_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "mail_deliveries", "events", on_delete: :cascade
  add_foreign_key "mail_deliveries", "participants", on_delete: :nullify
  add_foreign_key "participants", "events", on_delete: :cascade
  add_foreign_key "participants", "users", on_delete: :nullify
  add_foreign_key "plan_items", "events", on_delete: :cascade
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "time_slots", "events", on_delete: :cascade
  add_foreign_key "time_slots", "participants", column: ["participant_id", "event_id"], primary_key: ["id", "event_id"], name: "fk_time_slots_participant_in_event", on_delete: :cascade
end
