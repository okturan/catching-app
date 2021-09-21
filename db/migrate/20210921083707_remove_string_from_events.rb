class RemoveStringFromEvents < ActiveRecord::Migration[6.0]
  def change
    remove_column :events, :string
  end
end
