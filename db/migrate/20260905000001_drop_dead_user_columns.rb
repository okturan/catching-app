# These three columns were added in 2021 and never read by any code.
class DropDeadUserColumns < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :address
    remove_column :users, :phone_number
    remove_column :users, :time_zone_name
  end

  def down
    add_column :users, :address, :text
    add_column :users, :phone_number, :string
    add_column :users, :time_zone_name, :string
  end
end
