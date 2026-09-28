# Devise and has_secure_password both store a bcrypt digest of the bare
# password (no pepper was configured), so every account keeps its password
# through the rename. Sign-ins now live in sessions, one row per browser.
class ReplaceDeviseWithRailsAuthentication < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :encrypted_password, :password_digest
    change_column_default :users, :password_digest, from: "", to: nil
    change_column_default :users, :email, from: "", to: nil
    remove_index :users, :reset_password_token, unique: true
    remove_column :users, :reset_password_token, :string
    remove_column :users, :reset_password_sent_at, :datetime, precision: nil
    remove_column :users, :remember_created_at, :datetime, precision: nil

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
