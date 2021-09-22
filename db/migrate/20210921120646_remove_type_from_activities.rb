class RemoveTypeFromActivities < ActiveRecord::Migration[6.0]
  def change
    remove_column :activities, :type
  end
end
