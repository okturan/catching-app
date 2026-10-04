class AddEmailConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_confirmed_at, :datetime
    add_column :users, :login_link_used_at, :datetime
  end
end
