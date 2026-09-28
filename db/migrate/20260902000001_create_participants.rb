class CreateParticipants < ActiveRecord::Migration[8.1]
  def up
    create_table :participants do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string :role, null: false
      t.string :email, null: false
      t.string :name
      t.string :token_digest
      t.string :pending_token_digest
      t.datetime :pending_token_expires_at
      t.datetime :link_opened_at
      t.datetime :responded_at
      t.datetime :declined_at
      t.datetime :left_at
      t.string :time_zone
      t.timestamps
    end

    add_index :participants, :token_digest, unique: true
    add_index :participants, :pending_token_digest, unique: true
    add_index :participants, %i[event_id email], unique: true
    add_index :participants, :event_id, unique: true, where: "role = 'organizer'",
      name: "index_participants_one_organizer_per_event"
    add_index :participants, %i[user_id event_id], unique: true, where: "user_id IS NOT NULL"
    add_index :participants, %i[id event_id], unique: true
    add_index :participants, %i[role email created_at]

    add_check_constraint :participants, "role IN ('organizer', 'guest')", name: "participants_role_allowed"
    add_check_constraint :participants,
      "email = btrim(email) AND email !~ '[ABCDEFGHIJKLMNOPQRSTUVWXYZ]' AND position('@' IN email) > 1",
      name: "participants_email_normalized"
    add_check_constraint :participants, "token_digest IS NULL OR char_length(token_digest) = 64",
      name: "participants_token_digest_length"
    add_check_constraint :participants, "pending_token_digest IS NULL OR char_length(pending_token_digest) = 64",
      name: "participants_pending_token_digest_length"
    add_check_constraint :participants, "pending_token_expires_at IS NULL OR pending_token_digest IS NOT NULL",
      name: "participants_pending_token_pair"
    add_check_constraint :participants, "declined_at IS NULL OR responded_at IS NOT NULL",
      name: "participants_declined_implies_responded"
    add_check_constraint :participants,
      "left_at IS NULL OR (token_digest IS NULL AND pending_token_digest IS NULL AND declined_at IS NOT NULL AND user_id IS NULL AND role = 'guest')",
      name: "participants_left_is_revoked"

    create_table :mail_deliveries do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.references :participant, null: true, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :recipient_email, null: false
      t.string :canonical_recipient_email, null: false
      t.string :sender_email
      t.string :request_ip
      t.datetime :delivered_at
      t.datetime :failed_at
      t.string :error
      t.datetime :created_at, null: false
    end

    add_check_constraint :mail_deliveries,
      "kind IN ('organizer_link', 'invitation', 'response_confirmation', 'finalized', 'link_shown')",
      name: "mail_deliveries_kind_allowed"
    add_index :mail_deliveries, %i[canonical_recipient_email created_at]
    add_index :mail_deliveries, %i[sender_email created_at]
    add_index :mail_deliveries, %i[event_id canonical_recipient_email]
    add_index :mail_deliveries, %i[request_ip created_at]
    add_index :mail_deliveries, %i[participant_id created_at]
  end

  def down
    drop_table :mail_deliveries
    drop_table :participants
  end
end
