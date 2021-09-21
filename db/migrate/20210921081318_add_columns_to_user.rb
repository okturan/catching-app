class AddColumnsToUser < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :address, :text
    add_column :users, :phone_number, :integer
    add_column :users, :time_zone_name, :string
  end
end
