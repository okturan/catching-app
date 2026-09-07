class ReparentTimeSlotsToParticipants < ActiveRecord::Migration[8.1]
  def up
    add_column :time_slots, :participant_id, :bigint

    execute <<~SQL.squish
      INSERT INTO participants (event_id, user_id, role, email, name, responded_at, link_opened_at, created_at, updated_at)
      SELECT events.id, users.id, 'organizer', lower(btrim(users.email)),
             btrim(concat_ws(' ', users.first_name, users.last_name)),
             events.created_at, events.created_at, events.created_at, events.created_at
      FROM events
      JOIN users ON users.id = events.user_id
    SQL
    execute <<~SQL.squish
      INSERT INTO participants (event_id, user_id, role, email, name, responded_at, created_at, updated_at)
      SELECT user_events.event_id, users.id, 'guest', lower(btrim(users.email)),
             btrim(concat_ws(' ', users.first_name, users.last_name)),
             (SELECT MIN(slots.created_at) FROM time_slots slots
               WHERE slots.event_id = user_events.event_id AND slots.user_id = users.id),
             user_events.created_at, user_events.updated_at
      FROM user_events
      JOIN users ON users.id = user_events.user_id
      JOIN events ON events.id = user_events.event_id
      WHERE user_events.user_id <> events.user_id
    SQL
    execute <<~SQL.squish
      UPDATE time_slots SET participant_id = participants.id
      FROM participants
      WHERE participants.event_id = time_slots.event_id AND participants.user_id = time_slots.user_id
    SQL

    orphaned = select_value("SELECT COUNT(*) FROM time_slots WHERE participant_id IS NULL")
    say "Deleting #{orphaned} time slots with no participant"
    execute "DELETE FROM time_slots WHERE participant_id IS NULL"

    change_column_null :time_slots, :participant_id, false
    remove_index :time_slots, name: "index_time_slots_on_user_id_and_event_id_and_start_time"
    remove_index :time_slots, name: "index_time_slots_on_user_id"
    remove_index :time_slots, name: "index_time_slots_on_event_id"
    remove_foreign_key :time_slots, :users
    remove_foreign_key :time_slots, :events
    remove_column :time_slots, :user_id
    remove_column :time_slots, :end_time

    add_index :time_slots, %i[participant_id start_time], unique: true
    add_index :time_slots, %i[event_id start_time]
    add_foreign_key :time_slots, :participants, column: %i[participant_id event_id], primary_key: %i[id event_id],
      on_delete: :cascade, name: "fk_time_slots_participant_in_event"
    add_foreign_key :time_slots, :events, on_delete: :cascade
    add_check_constraint :time_slots, "start_time = date_bin('15 minutes', start_time, TIMESTAMP '2000-01-01')",
      name: "time_slots_start_time_quarter_hour"
  end

  # Structural reversal. Slots of participants without an account are lost,
  # which decision 2 of the design accepts: no production data exists.
  def down
    remove_check_constraint :time_slots, name: "time_slots_start_time_quarter_hour"
    remove_foreign_key :time_slots, name: "fk_time_slots_participant_in_event"
    remove_foreign_key :time_slots, :events
    remove_index :time_slots, %i[event_id start_time]
    remove_index :time_slots, %i[participant_id start_time]

    add_column :time_slots, :end_time, :datetime, precision: nil
    add_column :time_slots, :user_id, :bigint
    execute <<~SQL.squish
      UPDATE time_slots SET user_id = participants.user_id
      FROM participants WHERE participants.id = time_slots.participant_id
    SQL
    execute "DELETE FROM time_slots WHERE user_id IS NULL"
    change_column_null :time_slots, :user_id, false
    remove_column :time_slots, :participant_id

    add_foreign_key :time_slots, :users
    add_foreign_key :time_slots, :events
    add_index :time_slots, :user_id
    add_index :time_slots, :event_id
    add_index :time_slots, %i[user_id event_id start_time], unique: true
  end
end
