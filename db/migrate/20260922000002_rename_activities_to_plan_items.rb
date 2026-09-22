# The page has always called these the plan; now the code does too, and the
# length is in minutes by name, like the event's own.
class RenameActivitiesToPlanItems < ActiveRecord::Migration[8.1]
  def change
    rename_table :activities, :plan_items

    remove_check_constraint :plan_items, "duration IS NULL OR duration > 0 AND duration <= 1440", name: "activities_duration_bounded"
    remove_check_constraint :plan_items, "\"position\" >= 0", name: "activities_position_non_negative"
    rename_column :plan_items, :duration, :duration_minutes
    add_check_constraint :plan_items, "duration_minutes IS NULL OR duration_minutes > 0", name: "plan_items_duration_positive"
    add_check_constraint :plan_items, "\"position\" >= 0", name: "plan_items_position_non_negative"
  end
end
