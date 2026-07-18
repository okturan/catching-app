class HardenDataIntegrity < ActiveRecord::Migration[8.1]
  def up
    normalize_users
    normalize_events
    normalize_user_events
    normalize_time_slots
    normalize_activities

    change_column :users, :phone_number, :string, using: "phone_number::text"
    change_column_default :events, :status, false

    add_index :user_events, %i[user_id event_id], unique: true
    add_index :time_slots, %i[user_id event_id start_time], unique: true

    add_check_constraint :activities,
      "duration > 0",
      name: "activities_duration_positive",
      validate: false
    add_check_constraint :events,
      "start_time IS NULL OR end_time IS NULL OR end_time > start_time",
      name: "events_end_time_after_start_time",
      validate: false
    add_check_constraint :events,
      "status = FALSE OR (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)",
      name: "events_finalized_time_range",
      validate: false

    validate_check_constraint :activities, name: "activities_duration_positive"
    validate_check_constraint :events, name: "events_end_time_after_start_time"
    validate_check_constraint :events, name: "events_finalized_time_range"

    enforce_not_null :users, :first_name
    enforce_not_null :users, :last_name
    enforce_not_null :events, :name
    enforce_not_null :events, :description
    enforce_not_null :events, :status
    enforce_not_null :time_slots, :start_time
    enforce_not_null :activities, :name
    enforce_not_null :activities, :description
    enforce_not_null :activities, :duration
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Legacy scheduling data and phone numbers are normalized destructively"
  end

  private

  def normalize_users
    execute <<~SQL.squish
      UPDATE users
      SET first_name = split_part(email, '@', 1)
      WHERE first_name IS NULL OR btrim(first_name) = ''
    SQL
    execute <<~SQL.squish
      UPDATE users
      SET last_name = 'Member'
      WHERE last_name IS NULL OR btrim(last_name) = ''
    SQL
  end

  def normalize_events
    execute "UPDATE events SET name = 'Untitled event' WHERE name IS NULL OR btrim(name) = ''"
    execute "UPDATE events SET description = 'No description provided' WHERE description IS NULL OR btrim(description) = ''"
    execute "UPDATE events SET status = FALSE WHERE status IS NULL"
    normalize_finalized_events
    execute "UPDATE events SET start_time = NULL, end_time = NULL WHERE status = FALSE"
  end

  def normalize_finalized_events
    execute <<~SQL.squish
      UPDATE events
      SET status = FALSE, start_time = NULL, end_time = NULL
      WHERE status = TRUE
        AND (start_time IS NULL OR end_time IS NULL OR end_time < start_time)
    SQL
    execute <<~SQL.squish
      UPDATE events
      SET end_time = end_time + INTERVAL '1 hour'
      WHERE status = TRUE
    SQL
  end

  def normalize_user_events
    execute <<~SQL.squish
      DELETE FROM user_events invitations
      USING events
      WHERE invitations.event_id = events.id
        AND invitations.user_id = events.user_id
    SQL
    execute <<~SQL.squish
      DELETE FROM user_events duplicates
      USING user_events originals
      WHERE duplicates.id > originals.id
        AND duplicates.user_id = originals.user_id
        AND duplicates.event_id = originals.event_id
    SQL
  end

  def normalize_time_slots
    execute <<~SQL.squish
      DELETE FROM time_slots duplicates
      USING time_slots originals
      WHERE duplicates.id > originals.id
        AND duplicates.user_id = originals.user_id
        AND duplicates.event_id = originals.event_id
        AND duplicates.start_time = originals.start_time
    SQL
    execute "DELETE FROM time_slots WHERE start_time IS NULL"
  end

  def normalize_activities
    execute "UPDATE activities SET name = 'Untitled activity' WHERE name IS NULL OR btrim(name) = ''"
    execute "UPDATE activities SET description = 'No description provided' WHERE description IS NULL OR btrim(description) = ''"
    execute "UPDATE activities SET duration = 1 WHERE duration IS NULL OR duration <= 0"
  end

  def enforce_not_null(table, column)
    constraint_name = "#{table}_#{column}_not_null"
    quoted_column = connection.quote_column_name(column)

    add_check_constraint table,
      "#{quoted_column} IS NOT NULL",
      name: constraint_name,
      validate: false
    validate_check_constraint table, name: constraint_name
    change_column_null table, column, false
    remove_check_constraint table, name: constraint_name
  end
end
