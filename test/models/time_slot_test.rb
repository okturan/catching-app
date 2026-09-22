require "test_helper"

class TimeSlotTest < ActiveSupport::TestCase
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

  test "parses, normalizes, sorts, and deduplicates ISO timestamps" do
    parsed = TimeSlot.parse(
      "2030-01-15T12:00:00+02:00,2030-01-15T09:00:00Z,2030-01-15T12:00:00+02:00", slot_minutes: 60
    )

    assert_equal [ Time.utc(2030, 1, 15, 9), Time.utc(2030, 1, 15, 10) ], parsed
  end

  test "requires ISO 8601 timestamps" do
    error = assert_raises(Refusal) { TimeSlot.parse("tomorrow morning", slot_minutes: 60) }

    assert_equal "Time slots must use ISO 8601 timestamps", error.message
  end

  test "requires at least one timestamp" do
    error = assert_raises(Refusal) { TimeSlot.parse("", slot_minutes: 60) }

    assert_equal "Select at least one time slot", error.message
  end

  test "rejects timestamps spanning more than 31 days" do
    error = assert_raises(Refusal) do
      TimeSlot.parse("2030-01-01T10:00:00Z,2030-02-02T10:00:00Z", slot_minutes: 60)
    end

    assert_equal "Time slots must fit within a 31-day window", error.message
  end

  test "the cap is 31 days of 25-hour days, counted in the event's slots" do
    hourly = 776.times.map { |offset| (Time.utc(2030, 1, 11) + offset.hours).iso8601 }
    error = assert_raises(Refusal) { TimeSlot.parse(hourly.join(","), slot_minutes: 60) }
    assert_equal "Select no more than 775 time slots", error.message

    quarterly = 3101.times.map { |offset| (Time.utc(2030, 1, 11) + (offset * 15).minutes).iso8601 }
    error = assert_raises(Refusal) { TimeSlot.parse(quarterly.join(","), slot_minutes: 15) }
    assert_equal "Select no more than 3100 time slots", error.message
  end

  test "rejects instants from before yesterday" do
    error = assert_raises(Refusal) { TimeSlot.parse(2.days.ago.utc.iso8601, slot_minutes: 60) }

    assert_equal "Select time slots from today onward", error.message
  end
end
