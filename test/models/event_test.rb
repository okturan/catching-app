require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @event = events(:planning)
    @organizer = participants(:planning_organizer)
    @guest = participants(:planning_guest)
  end

  def plan(invitees: [ "bob@example.com" ], starts_at: [ Time.utc(2031, 2, 10, 9), Time.utc(2031, 2, 10, 10) ], **attributes)
    Event.plan!(
      attributes: { name: "Kickoff", description: "Find a time", slot_minutes: 60, time_zone: "UTC" }.merge(attributes),
      organizer: { email: "ann@example.com", name: "Ann", user: nil },
      starts_at: starts_at,
      invitee_emails: invitees
    )
  end

  test "requires a name, a description, a known zone and an allowed slot length" do
    event = Event.new

    assert_not event.valid?
    assert_includes event.errors[:name], "can't be blank"
    assert_includes event.errors[:description], "can't be blank"

    event.assign_attributes(name: "x", description: "y", slot_minutes: 45, time_zone: "Mars/Olympus")
    assert_not event.valid?
    assert_includes event.errors[:slot_minutes], "is not included in the list"
    assert_includes event.errors[:time_zone], "is not a known time zone"

    event.assign_attributes(slot_minutes: 30, time_zone: "Europe/Berlin", description: "x" * 2001)
    assert_not event.valid?
    assert_includes event.errors[:description], "is too long (maximum is 2000 characters)"
  end

  test "requires end time to follow start time and a complete range when finalized" do
    @event.start_time = Time.utc(2030, 1, 15, 11)
    @event.end_time = Time.utc(2030, 1, 15, 10)
    assert_not @event.valid?
    assert_includes @event.errors[:end_time], "must be after the start time"

    @event.assign_attributes(start_time: nil, end_time: nil, status: true)
    assert_not @event.valid?
    assert_includes @event.errors[:start_time], "can't be blank"
  end

  test "database rejects a finalized event without a whole number of slots" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) do
        @event.update_columns(status: true, start_time: Time.utc(2030, 1, 15, 10), end_time: Time.utc(2030, 1, 15, 10, 30))
      end
    end
  end

  test "plan! creates the event, organizer, offer and guests atomically" do
    event = nil
    assert_difference({ "Event.count" => 1, "Participant.count" => 3, "TimeSlot.count" => 2 }) do
      event = plan(invitees: [ "bob@example.com", "cy@example.com", "ann@example.com", "bob@example.com" ])
    end

    assert_equal "ann@example.com", event.organizer.email
    assert event.organizer.responded_at.present?
    assert_nil event.organizer.link_opened_at
    assert_equal %w[bob@example.com cy@example.com], event.guests.order(:email).pluck(:email)
    assert event.guests.all? { |guest| guest.token_digest.nil? }
  end

  test "plan! rolls back everything when the offer is invalid" do
    assert_no_difference([ "Event.count", "Participant.count", "TimeSlot.count" ]) do
      assert_raises(ArgumentError) { plan(starts_at: [ Time.utc(2031, 2, 10, 9, 15) ]) }
    end
  end

  test "alignment is anchored at local midnight in the event zone" do
    kolkata = plan(time_zone: "Asia/Kolkata", starts_at: [ Time.utc(2031, 2, 10, 4, 30) ])
    assert_nothing_raised { kolkata.ensure_aligned!([ Time.utc(2031, 2, 10, 5, 30) ]) }
    assert_raises(ArgumentError) { kolkata.ensure_aligned!([ Time.utc(2031, 2, 10, 5, 0) ]) }

    error = assert_raises(ArgumentError) { @event.ensure_aligned!([ Time.utc(2030, 1, 15, 10, 15) ]) }
    assert_equal "Select time slots on the event's 60-minute grid", error.message

    fifteen = plan(slot_minutes: 15, starts_at: [ Time.utc(2031, 2, 10, 9, 15) ])
    assert_raises(ArgumentError) { fifteen.ensure_aligned!([ Time.utc(2031, 2, 10, 9, 7) ]) }

    santiago = plan(time_zone: "America/Santiago", starts_at: [ Time.utc(2031, 2, 10, 12) ])
    gap_day = ActiveSupport::TimeZone["America/Santiago"].parse("2026-09-06 01:00")
    assert_nothing_raised { santiago.ensure_aligned!([ gap_day, gap_day + 1.hour ]) }

    lord_howe = plan(time_zone: "Australia/Lord_Howe", starts_at: [ Time.utc(2031, 2, 10, 12) ])
    after_shift = ActiveSupport::TimeZone["Australia/Lord_Howe"].parse("2026-04-05 03:30")
    assert_nothing_raised { lord_howe.ensure_aligned!([ after_shift ]) }
  end

  test "accessible scopes go through participations" do
    assert_includes Event.for_user(users(:owner)), @event
    assert_includes Event.for_user(users(:invitee)), @event
    assert_not_includes Event.for_user(users(:invitee)), events(:other_event)
    assert_empty Event.for_user(users(:outsider))
    assert_includes Event.organized_by(users(:owner)), @event
    assert_not_includes Event.organized_by(users(:invitee)), @event
  end

  test "consensus counts responders only and needs a guest" do
    assert_equal [ Time.utc(2030, 1, 15, 10) ], @event.mutually_available_start_times

    @guest.update!(declined_at: Time.current)
    assert_empty @event.mutually_available_start_times, "an organizer alone never has consensus"

    @guest.update!(declined_at: nil)
    silent = @event.participants.create!(role: :guest, email: "silent@example.com", token_digest: "a" * 64)
    assert_equal [ Time.utc(2030, 1, 15, 10) ], @event.mutually_available_start_times, "a silent invitee does not block"
    assert silent.persisted?
  end

  test "consensus is one statement" do
    assert_queries_count(1) { @event.mutually_available_start_times }
  end

  test "replacing availability is atomic and validates its input" do
    original = @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)

    assert_raises(ArgumentError) do
      @event.replace_time_slots!(participant: @organizer, starts_at: [ Time.utc(2030, 2, 1, 9), nil ])
    end
    assert_raises(ArgumentError) { @event.replace_time_slots!(participant: @organizer, starts_at: []) }
    assert_raises(ArgumentError) { @event.replace_time_slots!(participant: participants(:other_organizer), starts_at: original) }

    assert_equal original, @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
  end

  test "guests may only pick offered instants and duplicates collapse" do
    error = assert_raises(ArgumentError) do
      @event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2030, 1, 20, 9) ])
    end
    assert_equal "Select only time slots offered by the organizer", error.message

    @event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2030, 1, 15, 11), Time.utc(2030, 1, 15, 11) ])
    assert_equal [ Time.utc(2030, 1, 15, 11) ], @event.time_slots.where(participant_id: @guest.id).pluck(:start_time)
  end

  test "mark_unavailable! clears slots and excludes the guest" do
    @event.mark_unavailable!(participant: @guest)

    assert_equal 0, @guest.time_slots.count
    assert @guest.reload.declined_at.present?
    assert_empty @event.mutually_available_start_times
  end

  test "finalize! needs a reply, consensus and one continuous window of whole slots" do
    error = assert_raises(ArgumentError) { @event.finalize!(starts_at: [ Time.utc(2030, 1, 15, 11) ]) }
    assert_equal "Select only time slots available to every participant", error.message

    hours = [ 10, 11, 12 ].map { |hour| Time.utc(2030, 1, 15, hour) }
    @event.replace_time_slots!(participant: @organizer, starts_at: hours)
    @event.replace_time_slots!(participant: @guest, starts_at: hours)
    error = assert_raises(ArgumentError) { @event.finalize!(starts_at: [ hours[0], hours[2] ]) }
    assert_equal "Select one continuous meeting window", error.message

    @event.finalize!(starts_at: hours.first(2))
    assert_equal Time.utc(2030, 1, 15, 12), @event.end_time
    assert @event.status?
  end

  test "finalize! refuses an event nobody has replied to" do
    event = plan
    error = assert_raises(ArgumentError) { event.finalize!(starts_at: [ Time.utc(2031, 2, 10, 9) ]) }
    assert_equal "Wait for at least one reply before confirming", error.message
  end

  test "contiguity and the window follow the slot length" do
    event = plan(slot_minutes: 15, starts_at: [ 0, 15, 30, 60 ].map { |m| Time.utc(2031, 2, 10, 10) + m.minutes })
    guest = event.guests.first
    event.replace_time_slots!(participant: guest, starts_at: [ 0, 15, 30, 60 ].map { |m| Time.utc(2031, 2, 10, 10) + m.minutes })
    guest.update!(responded_at: Time.current)

    assert_raises(ArgumentError) { event.finalize!(starts_at: [ Time.utc(2031, 2, 10, 10), Time.utc(2031, 2, 10, 11) ]) }
    event.finalize!(starts_at: [ 0, 15, 30 ].map { |m| Time.utc(2031, 2, 10, 10) + m.minutes })
    assert_equal Time.utc(2031, 2, 10, 10, 45), event.end_time
  end

  test "slot length and zone freeze after the first reply" do
    @event.slot_minutes = 30
    assert_not @event.valid?
    assert_includes @event.errors[:slot_minutes], "cannot change after a guest has replied"

    fresh = plan
    fresh.slot_minutes = 30
    assert fresh.valid?
  end

  test "a stale availability request cannot write after finalization" do
    stale_event = Event.find(@event.id)
    existing = @event.time_slots.where(participant_id: @guest.id).order(:start_time).pluck(:start_time)

    @event.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ])

    locking_queries = capture_locking_queries do
      error = assert_raises(Event::ClosedError) do
        stale_event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2030, 1, 15, 11) ])
      end
      assert_equal "Availability is closed for this event", error.message
    end

    assert_equal 1, locking_queries.size
    assert_equal existing, @event.time_slots.where(participant_id: @guest.id).order(:start_time).pluck(:start_time)
  end

  test "a stale finalization request cannot overwrite the winning window" do
    first_request = Event.find(@event.id)
    stale_request = Event.find(@event.id)
    second_time = Time.utc(2030, 1, 15, 11)
    @event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2030, 1, 15, 10), second_time ])

    first_request.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ])

    locking_queries = capture_locking_queries do
      assert_raises(Event::ClosedError) { stale_request.finalize!(starts_at: [ second_time ]) }
    end

    assert_equal 1, locking_queries.size
    @event.reload
    assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
    assert_equal Time.utc(2030, 1, 15, 11), @event.end_time
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
