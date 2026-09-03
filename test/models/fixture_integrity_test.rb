require "test_helper"

# Fixture loading disables foreign-key triggers, so referential drift is
# caught here rather than at load time. Unique indexes and checks are still
# enforced while fixtures load.
class FixtureIntegrityTest < ActiveSupport::TestCase
  test "every slot belongs to a participant of the same event" do
    drifted = TimeSlot.joins(:participant).where("participants.event_id <> time_slots.event_id").count

    assert_equal 0, drifted
  end

  test "every participant references existing rows" do
    assert_equal 0, Participant.where.missing(:event).count
    assert_equal 0, Participant.where.not(user_id: nil).where.missing(:user).count
    assert_equal 0, MailDelivery.where.missing(:event).count
  end
end
