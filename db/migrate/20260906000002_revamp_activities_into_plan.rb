# Activities become the plan: ordered by position, duration and description
# optional, deleted with their event. Existing rows are numbered densely per
# event in id order.
class RevampActivitiesIntoPlan < ActiveRecord::Migration[8.1]
  def up
    add_column :activities, :position, :integer, null: false, default: 0
    execute <<~SQL.squish
      UPDATE activities SET position = numbered.position
      FROM (
        SELECT id, row_number() OVER (PARTITION BY event_id ORDER BY id) - 1 AS position
        FROM activities
      ) numbered
      WHERE numbered.id = activities.id
    SQL

    change_column_null :activities, :duration, true
    change_column_null :activities, :description, true

    remove_check_constraint :activities, name: "activities_duration_positive"
    add_check_constraint :activities, "duration IS NULL OR (duration > 0 AND duration <= 1440)",
      name: "activities_duration_bounded"
    add_check_constraint :activities, "position >= 0", name: "activities_position_non_negative"

    remove_index :activities, name: "index_activities_on_event_id"
    add_index :activities, %i[event_id position]

    remove_foreign_key :activities, :events
    add_foreign_key :activities, :events, on_delete: :cascade
  end

  # Items without a duration or description take the harden migration's own
  # normalization values before NOT NULL comes back.
  def down
    remove_foreign_key :activities, :events
    add_foreign_key :activities, :events

    remove_index :activities, %i[event_id position]
    add_index :activities, :event_id

    remove_check_constraint :activities, name: "activities_position_non_negative"
    remove_check_constraint :activities, name: "activities_duration_bounded"

    execute "UPDATE activities SET duration = 1 WHERE duration IS NULL"
    execute "UPDATE activities SET description = 'No description provided' WHERE description IS NULL"
    change_column_null :activities, :duration, false
    change_column_null :activities, :description, false
    add_check_constraint :activities, "duration > 0", name: "activities_duration_positive"

    remove_column :activities, :position
  end
end
