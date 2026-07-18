require "test_helper"

class TimeSlotTest < ActiveSupport::TestCase
  test "requires a start time" do
    slot = events(:planning).time_slots.build(user: users(:owner))

    assert_not slot.valid?
    assert_includes slot.errors[:start_time], "can't be blank"
  end

  test "prevents duplicate availability for one user and event" do
    existing = time_slots(:planning_owner_consensus)
    duplicate = TimeSlot.new(user: existing.user, event: existing.event, start_time: existing.start_time)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:start_time], "has already been taken"
  end
end
