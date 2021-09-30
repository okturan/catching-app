class AddDefaultValueToStatus < ActiveRecord::Migration[6.0]
  def change
    change_column :events, :status, :boolean, default: false
  end
end
