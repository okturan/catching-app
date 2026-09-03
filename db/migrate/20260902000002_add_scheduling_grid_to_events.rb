class AddSchedulingGridToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :slot_minutes, :integer, null: false, default: 30
    add_column :events, :time_zone, :string, null: false, default: "UTC"
    remove_column :events, :meeting_medium

    add_check_constraint :events, "slot_minutes IN (15, 30, 60)", name: "events_slot_minutes_allowed"
    add_check_constraint :events,
      "status = false OR (EXTRACT(EPOCH FROM (end_time - start_time))::bigint % (slot_minutes * 60)) = 0",
      name: "events_finalized_window_whole_slots"
  end

  def down
    remove_check_constraint :events, name: "events_finalized_window_whole_slots"
    remove_check_constraint :events, name: "events_slot_minutes_allowed"
    add_column :events, :meeting_medium, :string
    remove_column :events, :time_zone
    remove_column :events, :slot_minutes
  end
end
