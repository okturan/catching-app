# An event is finalized when it has a set time, so the window carries the
# state and the status flag goes. The product's own limits (reopen twice, a
# day-long meeting) move to the model; the checks keep what is always true.
class DeriveFinalizedFromTheWindow < ActiveRecord::Migration[8.1]
  def change
    reversible do |direction|
      direction.up { execute "UPDATE events SET start_time = NULL, end_time = NULL WHERE NOT status" }
      direction.down { execute "UPDATE events SET status = (start_time IS NOT NULL)" }
    end

    remove_check_constraint :events, "status = false OR start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time",
      name: "events_finalized_time_range"
    remove_check_constraint :events,
      "status = false OR (EXTRACT(epoch FROM end_time - start_time)::bigint % (slot_minutes * 60)::bigint) = 0",
      name: "events_finalized_window_whole_slots"
    remove_column :events, :status, :boolean, default: false, null: false

    add_check_constraint :events, "(start_time IS NULL) = (end_time IS NULL)", name: "events_window_complete"
    add_check_constraint :events,
      "start_time IS NULL OR (EXTRACT(epoch FROM end_time - start_time)::bigint % (slot_minutes * 60)::bigint) = 0",
      name: "events_window_whole_slots"

    remove_check_constraint :events, "reopen_count >= 0 AND reopen_count <= 2", name: "events_reopen_count_bounded"
    remove_check_constraint :events,
      "duration_minutes IS NULL OR duration_minutes > 0 AND duration_minutes <= 1440 AND (duration_minutes % 15) = 0",
      name: "events_duration_minutes_quarter_hour"
    add_check_constraint :events, "duration_minutes IS NULL OR duration_minutes > 0 AND (duration_minutes % 15) = 0",
      name: "events_duration_minutes_whole_quarters"
  end
end
