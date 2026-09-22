# Each of these is the leading column of a wider index that already serves
# the same lookups; the user_id one is covered by the partial unique index,
# since user_id = ? never matches NULL. Two generated names become readable.
class DropRedundantIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :participants, :event_id, name: "index_participants_on_event_id"
    remove_index :participants, :user_id, name: "index_participants_on_user_id"
    remove_index :mail_deliveries, :event_id, name: "index_mail_deliveries_on_event_id"
    remove_index :mail_deliveries, :participant_id, name: "index_mail_deliveries_on_participant_id"

    rename_index :mail_deliveries, "idx_on_canonical_recipient_email_created_at_1846ffef76", "index_mail_deliveries_on_recipient_and_created_at"
    rename_index :mail_deliveries, "idx_on_event_id_canonical_recipient_email_79ed6ea4e6", "index_mail_deliveries_on_event_and_recipient"
  end
end
