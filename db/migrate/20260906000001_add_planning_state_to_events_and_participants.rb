# Planning state: event facts (place, join link, planned length), the revision
# counters behind change notices, the offer-revision stamp, cancellation and
# reopening, and the voided-reply mark on participants. Checks are added
# validated in one step: the tables hold no production data.
class AddPlanningStateToEventsAndParticipants < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :place, :string
    add_column :events, :place_url, :string
    add_column :events, :duration_minutes, :integer
    add_column :events, :revision, :integer, null: false, default: 0
    add_column :events, :notified_revision, :integer, null: false, default: 0
    add_column :events, :offer_revised_at, :datetime
    add_column :events, :offer_revision_added, :integer, null: false, default: 0
    add_column :events, :offer_revision_removed, :integer, null: false, default: 0
    add_column :events, :cancelled_at, :datetime
    add_column :events, :reopened_at, :datetime
    add_column :events, :reopen_count, :integer, null: false, default: 0
    add_column :participants, :reply_voided_at, :datetime

    add_check_constraint :events, "place_url IS NULL OR place_url ~ '^[Hh][Tt][Tt][Pp][Ss]?://'",
      name: "events_place_url_scheme"
    add_check_constraint :events,
      "duration_minutes IS NULL OR (duration_minutes > 0 AND duration_minutes <= 1440 AND duration_minutes % 15 = 0)",
      name: "events_duration_minutes_quarter_hour"
    add_check_constraint :events, "notified_revision >= 0 AND notified_revision <= revision",
      name: "events_revisions_ordered"
    add_check_constraint :events,
      "(offer_revised_at IS NULL AND offer_revision_added = 0 AND offer_revision_removed = 0) " \
      "OR (offer_revised_at IS NOT NULL AND offer_revision_added + offer_revision_removed > 0)",
      name: "events_offer_revision_counts"
    add_check_constraint :events, "reopen_count BETWEEN 0 AND 2", name: "events_reopen_count_bounded"
    add_check_constraint :participants,
      "reply_voided_at IS NULL OR (responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL AND role = 'guest')",
      name: "participants_voided_is_open_reply"
  end

  def down
    remove_check_constraint :participants, name: "participants_voided_is_open_reply"
    remove_check_constraint :events, name: "events_reopen_count_bounded"
    remove_check_constraint :events, name: "events_offer_revision_counts"
    remove_check_constraint :events, name: "events_revisions_ordered"
    remove_check_constraint :events, name: "events_duration_minutes_quarter_hour"
    remove_check_constraint :events, name: "events_place_url_scheme"

    remove_column :participants, :reply_voided_at
    remove_column :events, :reopen_count
    remove_column :events, :reopened_at
    remove_column :events, :cancelled_at
    remove_column :events, :offer_revision_removed
    remove_column :events, :offer_revision_added
    remove_column :events, :offer_revised_at
    remove_column :events, :notified_revision
    remove_column :events, :revision
    remove_column :events, :duration_minutes
    remove_column :events, :place_url
    remove_column :events, :place
  end
end
