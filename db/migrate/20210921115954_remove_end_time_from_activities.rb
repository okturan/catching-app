class RemoveEndTimeFromActivities < ActiveRecord::Migration[6.0]
  def change
    remove_column :activities, :end_time, :datetime
  end
end
