require "test_helper"

# Fixture loading disables foreign-key triggers, so referential drift is
# caught here rather than at load time. Unique indexes and checks are still
# enforced while fixtures load.
class FixtureIntegrityTest < ActiveSupport::TestCase
  test "every slot belongs to a participant of the same event" do
    drifted = TimeSlot.joins(:participant).where("participants.event_id <> time_slots.event_id").count

    assert_equal 0, drifted
  end

  # Offer revision deletes guest picks at removed instants, so the fixture
  # database must already obey the rule every write keeps: a guest never holds
  # an instant the organizer does not offer.
  test "every guest slot is inside the organizer's offer" do
    stray = TimeSlot.joins(:participant).merge(Participant.guest).where(<<~SQL.squish).count
      NOT EXISTS (
        SELECT 1 FROM time_slots offer
        JOIN participants organizers ON organizers.id = offer.participant_id AND organizers.role = 'organizer'
        WHERE offer.event_id = time_slots.event_id AND offer.start_time = time_slots.start_time
      )
    SQL

    assert_equal 0, stray
  end

  test "every participant references existing rows" do
    assert_equal 0, Participant.where.missing(:event).count
    assert_equal 0, Participant.where.not(user_id: nil).where.missing(:user).count
    assert_equal 0, MailDelivery.where.missing(:event).count
  end
end
