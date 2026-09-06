# Three more ledger kinds: the coalesced change notice, the cancellation and
# the reopening mail. Templates and senders arrive with their own changes.
class ExtendMailDeliveryKinds < ActiveRecord::Migration[8.1]
  FOUNDATION_KINDS = %w[organizer_link invitation response_confirmation finalized link_shown].freeze
  PLANNING_KINDS = %w[event_updated cancelled reopened].freeze

  def up
    remove_check_constraint :mail_deliveries, name: "mail_deliveries_kind_allowed"
    add_check_constraint :mail_deliveries, kind_check(FOUNDATION_KINDS + PLANNING_KINDS),
      name: "mail_deliveries_kind_allowed"
  end

  # Fails while ledger rows of the three new kinds exist: the ledger is the
  # audit trail behind every send cap and is never rewritten.
  def down
    remove_check_constraint :mail_deliveries, name: "mail_deliveries_kind_allowed"
    add_check_constraint :mail_deliveries, kind_check(FOUNDATION_KINDS), name: "mail_deliveries_kind_allowed"
  end

  private

  def kind_check(kinds)
    "kind IN (#{kinds.map { |kind| "'#{kind}'" }.join(', ')})"
  end
end
