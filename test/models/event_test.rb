require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "requires a name and description" do
    event = users(:owner).events.build

    assert_not event.valid?
    assert_includes event.errors[:name], "can't be blank"
    assert_includes event.errors[:description], "can't be blank"
  end

  test "requires an organizer" do
    event = Event.new(name: "Planning", description: "Choose a time")

    assert_not event.valid?
    assert_includes event.errors[:user], "must exist"
  end

  test "requires end time to follow start time" do
    event = events(:planning)
    event.start_time = Time.zone.parse("2030-01-15 11:00:00")
    event.end_time = Time.zone.parse("2030-01-15 10:00:00")

    assert_not event.valid?
    assert_includes event.errors[:end_time], "must be after the start time"
  end

  test "requires a complete time range when finalized" do
    event = events(:planning)
    event.status = true

    assert_not event.valid?
    assert_includes event.errors[:start_time], "can't be blank"
    assert_includes event.errors[:end_time], "can't be blank"
  end

  test "database rejects a finalized event without a valid time range" do
    event = events(:planning)

    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) do
        event.update_columns(status: true, start_time: nil, end_time: nil)
      end
    end
  end

  test "accessible scope includes owned and invited events only" do
    owner_events = Event.accessible_to(users(:owner))
    invitee_events = Event.accessible_to(users(:invitee))
    outsider_events = Event.accessible_to(users(:outsider))

    assert_includes owner_events, events(:planning)
    assert_includes owner_events, events(:finalized)
    assert_includes invitee_events, events(:planning)
    assert_includes invitee_events, events(:finalized)
    assert_not_includes invitee_events, events(:other_event)
    assert_empty outsider_events
  end

  test "returns only time slots shared by every participant" do
    event = events(:planning)

    assert_equal [ Time.zone.parse("2030-01-15 10:00:00") ], event.mutually_available_start_times
  end

  test "replacing availability is atomic" do
    event = events(:planning)
    original_times = event.time_slots.where(user: users(:owner)).order(:start_time).pluck(:start_time)

    assert_raises(ActiveRecord::RecordInvalid) do
      event.replace_time_slots!(
        user: users(:owner),
        starts_at: [ Time.zone.parse("2030-02-01 09:00:00"), nil ]
      )
    end

    assert_equal original_times, event.time_slots.where(user: users(:owner)).order(:start_time).pluck(:start_time)
  end

  test "a stale availability request cannot write after finalization" do
    event = events(:planning)
    stale_event = Event.find(event.id)
    existing_times = event.time_slots.where(user: users(:invitee)).order(:start_time).pluck(:start_time)

    event.finalize!(starts_at: [ Time.zone.parse("2030-01-15 10:00:00") ])

    locking_queries = capture_locking_queries do
      error = assert_raises(Event::ClosedError) do
        stale_event.replace_time_slots!(
          user: users(:invitee),
          starts_at: [ Time.zone.parse("2030-01-15 11:00:00") ]
        )
      end

      assert_equal "Availability is closed for this event", error.message
    end

    assert_equal 1, locking_queries.size
    assert_equal existing_times, event.time_slots.where(user: users(:invitee)).order(:start_time).pluck(:start_time)
  end

  test "a stale finalization request cannot overwrite the winning window" do
    event = events(:planning)
    first_request = Event.find(event.id)
    stale_request = Event.find(event.id)
    second_time = Time.zone.parse("2030-01-15 11:00:00")
    event.time_slots.create!(user: users(:invitee), start_time: second_time)

    first_request.finalize!(starts_at: [ Time.zone.parse("2030-01-15 10:00:00") ])

    locking_queries = capture_locking_queries do
      assert_raises(Event::ClosedError) do
        stale_request.finalize!(starts_at: [ second_time ])
      end
    end

    assert_equal 1, locking_queries.size
    event.reload
    assert_equal Time.zone.parse("2030-01-15 10:00:00"), event.start_time
    assert_equal Time.zone.parse("2030-01-15 11:00:00"), event.end_time
  end

  private

  def capture_locking_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _id, payload|
      queries << payload[:sql] if payload[:sql].match?(/FOR UPDATE/)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
