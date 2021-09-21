class RemoveStartTimeFromActivities < ActiveRecord::Migration[6.0]
  def change
    remove_column :activities, :start_time, :datetime
  end
end
