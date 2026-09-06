require "test_helper"

class TimeSlotTest < ActiveSupport::TestCase
  test "requires a start time" do
    slot = events(:planning).time_slots.build(participant: participants(:planning_organizer))

    assert_not slot.valid?
    assert_includes slot.errors[:start_time], "can't be blank"
  end

  test "copies the event from the participant and refuses a foreign participant" do
    slot = TimeSlot.new(participant: participants(:planning_guest), start_time: Time.utc(2030, 1, 16, 10))
    assert slot.valid?
    assert_equal events(:planning).id, slot.event_id

    slot.event = events(:other_event)
    assert_not slot.valid?
    assert_includes slot.errors[:participant], "belongs to another event"
  end

  test "the composite foreign key rejects a participant of another event" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      TimeSlot.transaction(requires_new: true) do
        TimeSlot.insert_all!([ { participant_id: participants(:planning_guest).id, event_id: events(:other_event).id,
          start_time: Time.utc(2030, 1, 16, 10) } ])
      end
    end
  end

  test "duplicate instants for one participant are rejected" do
    existing = time_slots(:planning_owner_consensus)

    assert_raises(ActiveRecord::RecordNotUnique) do
      TimeSlot.transaction(requires_new: true) do
        TimeSlot.insert_all!([ { participant_id: existing.participant_id, event_id: existing.event_id, start_time: existing.start_time } ])
      end
    end
  end

  test "the database rejects instants off the quarter hour" do
    [ Time.utc(2030, 1, 16, 10, 7, 30), Time.utc(2030, 1, 16, 10, 0, 0, 500_000) ].each do |bad|
      assert_raises(ActiveRecord::StatementInvalid) do
        TimeSlot.transaction(requires_new: true) do
          TimeSlot.insert_all!([ { participant_id: participants(:planning_guest).id, event_id: events(:planning).id, start_time: bad } ])
        end
      end
    end
  end

  test "deleting a participant deletes its slots through the database" do
    guest = participants(:planning_guest)
    assert_equal 1, TimeSlot.where(participant_id: guest.id).count

    Participant.where(id: guest.id).delete_all

    assert_equal 0, TimeSlot.where(participant_id: guest.id).count
  end
end
