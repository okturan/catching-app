class DropUserOwnership < ActiveRecord::Migration[8.1]
  def up
    drop_table :user_events
    remove_reference :events, :user, foreign_key: true, index: true
  end

  # events.user_id comes back nullable: accountless organizers have no user.
  def down
    add_reference :events, :user, foreign_key: true, index: true
    execute <<~SQL.squish
      UPDATE events SET user_id = participants.user_id
      FROM participants
      WHERE participants.event_id = events.id AND participants.role = 'organizer' AND participants.user_id IS NOT NULL
    SQL

    create_table :user_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.timestamps
    end
    add_index :user_events, %i[user_id event_id], unique: true
    execute <<~SQL.squish
      INSERT INTO user_events (user_id, event_id, created_at, updated_at)
      SELECT user_id, event_id, created_at, updated_at
      FROM participants
      WHERE role = 'guest' AND user_id IS NOT NULL AND left_at IS NULL
    SQL
  end
end
