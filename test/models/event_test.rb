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

  test "place is squished, blank becomes nil and 200 characters is the limit" do
    event = plan(place: "  Ege's   place, Kadıköy ")
    assert_equal "Ege's place, Kadıköy", event.place

    event.update!(place: "   ")
    assert_nil event.place

    event.place = "x" * 201
    assert_not event.valid?
    assert_includes event.errors[:place], "is too long (maximum is 200 characters)"
  end

  test "place_url keeps everything but a downcased scheme and refuses non-web addresses" do
    @event.place_url = " HTTPS://Zoom.us/J/1 "
    assert @event.valid?
    assert_equal "https://Zoom.us/J/1", @event.place_url

    @event.place_url = "   "
    assert_nil @event.place_url

    [ "javascript:alert(1)", "ftp://files.example", "https://user@evil.example", "https://", "not a url", "//zoom.us", "https:///path" ].each do |bad|
      @event.place_url = bad
      assert_not @event.valid?, "#{bad.inspect} should be refused"
      assert_equal [ "must be a web address starting with http:// or https://" ], @event.errors[:place_url], bad.inspect
    end

    @event.place_url = "https://#{'a' * 1990}.example"
    assert_not @event.valid?
    assert_includes @event.errors[:place_url], "must be a web address starting with http:// or https://"
  end

  test "database refuses a place_url the model did not see" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) { @event.update_columns(place_url: "javascript:x") }
    end
    assert_nil @event.reload.place_url
  end

  test "duration_minutes is a whole number of slots, at most a day" do
    thirty = plan(slot_minutes: 30, starts_at: [ Time.utc(2031, 2, 10, 9) ])
    thirty.duration_minutes = 45
    assert_not thirty.valid?
    assert_equal [ "must be a whole number of 30-minute slots" ], thirty.errors[:duration_minutes]

    fifteen = plan(slot_minutes: 15, starts_at: [ Time.utc(2031, 2, 10, 9) ])
    fifteen.update!(duration_minutes: 45)
    assert_equal 45, fifteen.reload.duration_minutes

    fifteen.duration_minutes = 1441
    assert_not fifteen.valid?
    assert_equal [ "must be at most 24 hours" ], fifteen.errors[:duration_minutes]

    fifteen.duration_minutes = 0
    assert_not fifteen.valid?
    assert_equal [ "must be greater than 0" ], fifteen.errors[:duration_minutes]

    fifteen.duration_minutes = "abc"
    assert_not fifteen.valid?
    assert_equal [ "is not a number" ], fifteen.errors[:duration_minutes]

    fifteen.duration_minutes = ""
    assert fifteen.valid?
    assert_nil fifteen.duration_minutes

    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) { fifteen.update_columns(duration_minutes: 20) }
    end
  end

  test "a planned length is a hint that finalize! never reads" do
    @event.update!(duration_minutes: 120)

    @event.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ])

    assert @event.status?
    assert_equal 120, @event.reload.duration_minutes
    assert_equal Time.utc(2030, 1, 15, 11), @event.end_time
  end

  test "finalize! bumps the revision with the window so the published file outranks earlier ones" do
    @event.update_columns(revision: 3, notified_revision: 3)

    @event.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ])

    @event.reload
    assert @event.status?
    assert_equal 4, @event.revision
    assert_equal 3, @event.notified_revision, "the batch, not the model, marks guests told"
    assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
  end

  test "plan_timeline derives starts from a window handed to it, whatever the row says" do
    pizza = @event.activities.first
    movie = @event.activities.create!(name: "Movie", duration: 120, position: 1)

    assert_equal [ nil, nil ], @event.plan_timeline.map(&:last), "pending: nothing derived"
    assert_equal [ [ pizza, Time.utc(2030, 1, 15, 10) ], [ movie, Time.utc(2030, 1, 15, 11, 30) ] ],
      @event.plan_timeline(from: Time.utc(2030, 1, 15, 10))
  end

  test "update_details! bumps the revision once per changed save and returns the change set" do
    @event.update_columns(revision: 3, notified_revision: 3)

    changes = @event.update_details!(place: "Ege's place", duration_minutes: 120)

    assert_equal %w[duration_minutes place], changes.keys.sort
    assert_equal [ nil, "Ege's place" ], changes["place"]
    @event.reload
    assert_equal 4, @event.revision
    assert_equal "Ege's place", @event.place
    assert_equal 120, @event.duration_minutes
  end

  test "update_details! with nothing changed bumps nothing" do
    updated_at = @event.updated_at

    changes = @event.update_details!(name: @event.name, place: "")

    assert_empty changes
    @event.reload
    assert_equal 0, @event.revision
    assert_equal updated_at, @event.updated_at
  end

  test "update_details! is refused on a cancelled event and allowed on a finalized one" do
    @event.update_columns(cancelled_at: Time.current)
    error = assert_raises(Event::ClosedError) { @event.update_details!(name: "New name") }
    assert_equal "This event was cancelled", error.message
    assert_equal "Planning session", @event.reload.name

    finalized = events(:finalized)
    finalized.update_details!(place: "Zoom")
    finalized.reload
    assert_equal 1, finalized.revision
    assert_equal "Zoom", finalized.place
    assert finalized.status?
    assert_equal Time.utc(2030, 1, 15, 10), finalized.start_time
    assert_equal Time.utc(2030, 1, 15, 11), finalized.end_time
  end

  test "update_details! validates inside the lock and leaves slots and participants alone" do
    slots = @event.time_slots.order(:id).map(&:attributes)
    people = @event.participants.order(:id).map(&:attributes)

    assert_raises(ActiveRecord::RecordInvalid) { @event.update_details!(name: "Renamed", place_url: "ftp://files.example") }
    assert_equal "Planning session", @event.reload.name

    @event.update_details!(name: "Renamed", description: "Same people, new name")
    assert_equal "Renamed", @event.reload.name
    assert_equal slots, @event.time_slots.order(:id).map(&:attributes)
    assert_equal people, @event.participants.order(:id).map(&:attributes)
  end

  test "plan writes are locked, refused once cancelled and each bumps the revision once" do
    @event.update_columns(revision: 3, notified_revision: 3)

    item = @event.add_plan_item!(name: " Pizza ", duration: 30)
    assert_equal [ "Pizza", 1 ], [ item.name, item.position ]
    @event.update_plan_item!(item, duration: 45)
    @event.move_plan_item!(item, 0)
    @event.remove_plan_item!(item)

    assert_equal 7, @event.reload.revision
    assert_equal [ "Board games" ], @event.activities.pluck(:name)

    @event.update_columns(cancelled_at: Time.current)
    error = assert_raises(Event::ClosedError) { @event.add_plan_item!(name: "Late") }
    assert_equal "This event was cancelled", error.message
    assert_raises(Event::ClosedError) { @event.update_plan_item!(activities(:planning_activity), name: "Late") }
    assert_raises(Event::ClosedError) { @event.move_plan_item!(activities(:planning_activity), 0) }
    assert_raises(Event::ClosedError) { @event.remove_plan_item!(activities(:planning_activity)) }
    assert_equal 7, @event.reload.revision
    assert_equal [ "Board games" ], @event.activities.reload.pluck(:name)
  end

  test "the first plan item starts at zero and a refused item bumps nothing" do
    event = events(:other_event)

    first = event.add_plan_item!(name: "Pizza")
    assert_equal 0, first.position
    assert_raises(ActiveRecord::RecordInvalid) { event.add_plan_item!(name: "") }
    assert_raises(ActiveRecord::RecordInvalid) { event.update_plan_item!(first, duration: 1441) }

    assert_equal 1, event.reload.revision
    assert_equal [ "Pizza" ], event.activities.pluck(:name)
    assert_nil first.reload.duration
  end

  test "move_plan_item! renumbers ties densely, clamps the target and is a no-op at the ends" do
    event = events(:other_event)
    a, b, c = %w[A B C].map { |name| event.activities.create!(name: name, position: 0) }

    event.move_plan_item!(a, 1)
    assert_equal [ b, a, c ], event.activities.reload.to_a
    assert_equal [ 0, 1, 2 ], event.activities.pluck(:position)
    assert_equal 1, event.reload.revision

    event.move_plan_item!(c, 0)
    assert_equal [ c, b, a ], event.activities.reload.to_a
    event.move_plan_item!(c, 99)
    assert_equal [ b, a, c ], event.activities.reload.to_a
    assert_equal [ 0, 1, 2 ], event.activities.pluck(:position)
    assert_equal 3, event.reload.revision

    event.move_plan_item!(b, -1)
    event.move_plan_item!(c, 5)
    assert_equal [ b, a, c ], event.activities.reload.to_a
    assert_equal 3, event.reload.revision

    assert_raises(ActiveRecord::RecordNotFound) { event.move_plan_item!(activities(:planning_activity), 0) }
    assert_equal 3, event.reload.revision
  end

  test "plan_timeline derives starts once set and not cancelled, and stops after an item without a length" do
    finalized = events(:finalized)
    pizza = finalized.activities.create!(name: "Pizza", duration: 30, position: 1)
    dune = finalized.activities.create!(name: "Dune", duration: 155, position: 2)

    assert_equal [ [ pizza, Time.utc(2030, 1, 15, 10) ], [ dune, Time.utc(2030, 1, 15, 10, 30) ] ], finalized.plan_timeline
    assert_equal 185, finalized.plan_minutes
    assert_equal 60, finalized.window_minutes

    arrive = finalized.activities.create!(name: "Arrive", position: 0)
    finalized.activities.reset
    assert_equal [ [ arrive, Time.utc(2030, 1, 15, 10) ], [ pizza, nil ], [ dune, nil ] ], finalized.plan_timeline

    assert_equal [ [ activities(:planning_activity), nil ] ], @event.plan_timeline
    assert_nil @event.window_minutes

    finalized.update_columns(cancelled_at: Time.current)
    assert_equal [ nil, nil, nil ], finalized.plan_timeline.map(&:last)
  end

  test "cancel! stamps the event once, bumps the revision and deletes nothing" do
    @event.update_columns(revision: 3, notified_revision: 3)
    MailDelivery.create!(event: @event, participant: @guest, kind: :invitation, recipient_email: @guest.email)
    counts = -> { [ Event.count, Participant.count, TimeSlot.count, Activity.count, MailDelivery.count ] }
    before = counts.call

    @event.cancel!

    @event.reload
    assert @event.cancelled?
    assert_in_delta Time.current, @event.cancelled_at, 5.seconds
    assert_equal 4, @event.revision
    assert_not @event.open?
    assert @event.closed?
    assert_not @event.status?
    assert_equal before, counts.call
    assert_equal @guest, Participant.find_by_token(raw_token(:planning_guest))
    assert_equal @organizer, Participant.find_by_token(raw_token(:planning_organizer))
    assert_equal users(:invitee).id, @guest.reload.user_id

    error = assert_raises(Event::ClosedError) { @event.cancel! }
    assert_equal "This event was cancelled", error.message
    assert_equal 4, @event.reload.revision
  end

  test "cancelling a finalized event keeps its window" do
    finalized = events(:finalized)

    finalized.cancel!

    finalized.reload
    assert finalized.cancelled?
    assert finalized.status?
    assert finalized.closed?
    assert_not finalized.open?
    assert_equal Time.utc(2030, 1, 15, 10), finalized.start_time
    assert_equal Time.utc(2030, 1, 15, 11), finalized.end_time
    assert_equal 1, finalized.revision
  end

  test "cancelled_at cannot be changed or cleared once set" do
    @event.cancel!
    stamped = @event.reload.cancelled_at

    @event.cancelled_at = 1.day.ago
    assert_not @event.valid?
    assert_equal [ "cannot be changed once cancelled" ], @event.errors[:cancelled_at]

    @event.cancelled_at = nil
    assert_not @event.valid?
    assert_equal [ "cannot be changed once cancelled" ], @event.errors[:cancelled_at]

    assert_raises(ActiveRecord::RecordInvalid) { @event.update!(cancelled_at: nil) }
    assert_equal stamped, @event.reload.cancelled_at
  end

  test "open, finalized and cancelled are three states and not_cancelled reads two of them" do
    assert @event.open?
    assert_not @event.closed?
    assert_not events(:finalized).open?
    assert events(:finalized).closed?
    assert_includes Event.not_cancelled, @event
    assert_includes Event.not_cancelled, events(:finalized)

    @event.cancel!

    assert_not_includes Event.not_cancelled, @event
    assert_includes Event.not_cancelled, events(:finalized)
  end

  test "every writer refuses a cancelled event with one message before any other check" do
    finalized = events(:finalized)
    finalized.cancel!
    error = assert_raises(Event::ClosedError) { finalized.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ]) }
    assert_equal "This event was cancelled", error.message, "cancelled wins over the finalized message"

    @event.cancel!
    slots = @event.time_slots.order(:id).pluck(:id)
    writers = {
      "replace_time_slots!" => -> { @event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2030, 1, 15, 11) ]) },
      "mark_unavailable!" => -> { @event.mark_unavailable!(participant: @guest) },
      "finalize!" => -> { @event.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ]) },
      "update_details!" => -> { @event.update_details!(name: "Renamed") },
      "add_plan_item!" => -> { @event.add_plan_item!(name: "Late") },
      "revise_offer!" => -> { @event.revise_offer!(starts_at: [ Time.utc(2030, 1, 15, 12) ]) },
      "reopen!" => -> { @event.reopen! }
    }
    writers.each do |name, writer|
      error = assert_raises(Event::ClosedError, name) { writer.call }
      assert_equal "This event was cancelled", error.message, name
    end
    assert_equal slots, @event.time_slots.order(:id).pluck(:id)
    assert_nil @guest.reload.declined_at
    @event.reload
    assert_equal "Planning session", @event.name
    assert_equal 1, @event.revision
    assert_equal [ "Board games" ], @event.activities.pluck(:name)
  end

  test "reopen! withdraws the window, keeps every row and returns what was set" do
    finalized = events(:finalized)
    finalized.update_columns(revision: 5, notified_revision: 5)
    guest = participants(:finalized_guest)
    rows = -> { [ finalized.time_slots.order(:id).pluck(:participant_id, :start_time), finalized.participants.order(:id).pluck(:responded_at, :declined_at, :reply_voided_at, :token_digest, :pending_token_digest, :user_id) ] }
    before = rows.call

    window = finalized.reopen!

    assert_equal [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ], window
    finalized.reload
    assert_not finalized.status?
    assert finalized.open?
    assert_nil finalized.start_time
    assert_nil finalized.end_time
    assert_in_delta Time.current, finalized.reopened_at, 5.seconds
    assert_equal 1, finalized.reopen_count
    assert_equal 6, finalized.revision
    assert_equal 5, finalized.notified_revision, "the batch, not the model, marks guests told"
    assert_equal before, rows.call
    assert guest.reload.counting?
    assert_equal [ Time.utc(2030, 1, 15, 10) ], finalized.mutually_available_start_times
    assert_nil finalized.window_minutes
    assert finalized.plan_timeline.all? { |_activity, start| start.nil? }, "derived starts need a set time"
  end

  test "reopen! refuses a pending event, a cancelled one and a third time with the exact messages" do
    error = assert_raises(ArgumentError) { @event.reopen! }
    assert_equal "Only a set time can be reopened", error.message
    assert_equal 0, @event.reload.reopen_count
    assert_equal 0, @event.revision

    finalized = events(:finalized)
    finalized.update_columns(reopen_count: 2, revision: 9)
    error = assert_raises(ArgumentError) { finalized.reopen! }
    assert_equal "This event was reopened twice already. Cancel it and plan a new one.", error.message
    finalized.reload
    assert finalized.status?
    assert_equal Time.utc(2030, 1, 15, 10), finalized.start_time
    assert_equal 2, finalized.reopen_count
    assert_equal 9, finalized.revision

    finalized.update_columns(reopen_count: 1)
    finalized.cancel!
    error = assert_raises(Event::ClosedError) { finalized.reopen! }
    assert_equal "This event was cancelled", error.message, "cancelled wins over every other check"
    assert finalized.reload.status?
    assert_equal 1, finalized.reopen_count
  end

  test "the reopen count is a real check" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) { @event.update_columns(reopen_count: 3) }
    end
  end

  test "finalize! after reopen! sets a new window, bumps the revision again and the second reopen is the last" do
    finalized = events(:finalized)
    finalized.update_columns(revision: 6)

    finalized.reopen!
    finalized.reload.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ])

    finalized.reload
    assert finalized.status?
    assert_equal Time.utc(2030, 1, 15, 10), finalized.start_time
    assert_equal Time.utc(2030, 1, 15, 11), finalized.end_time
    assert_equal 8, finalized.revision
    assert_equal 1, finalized.reopen_count

    finalized.reopen!
    assert_equal 2, finalized.reload.reopen_count
    assert_equal 9, finalized.revision
    finalized.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ])
    assert_equal 10, finalized.reload.revision
    error = assert_raises(ArgumentError) { finalized.reopen! }
    assert_equal Event::REOPEN_LIMIT_MESSAGE, error.message
    assert finalized.reload.status?
  end

  test "every_offer_past? reads the organizer's offer against the parser cut-off" do
    assert_not @event.every_offer_past?

    past = 3.days.ago.beginning_of_hour
    @event.time_slots.where(start_time: Time.utc(2030, 1, 15, 10)).update_all(start_time: past)
    @event.time_slots.where(start_time: Time.utc(2030, 1, 15, 11)).update_all(start_time: past - 1.hour)
    assert @event.every_offer_past?

    @event.time_slots.create!(participant: @organizer, start_time: 2.days.from_now.beginning_of_hour)
    assert_not @event.every_offer_past?

    @event.time_slots.delete_all
    assert_not @event.every_offer_past?, "no offer at all is not a past offer"
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

  test "consensus excludes a voided guest and needs a counting one" do
    voided = participants(:planning_pending)
    voided.update_columns(responded_at: 2.days.ago, reply_voided_at: 1.day.ago)

    assert_queries_count(1) { assert_equal [ Time.utc(2030, 1, 15, 10) ], @event.mutually_available_start_times }

    @guest.update_columns(reply_voided_at: Time.current)
    assert_empty @event.mutually_available_start_times, "voided guests are outside the denominator and the guard"
    error = assert_raises(ArgumentError) { @event.finalize!(starts_at: [ Time.utc(2030, 1, 15, 10) ]) }
    assert_equal "Wait for at least one reply before confirming", error.message
    assert_not @event.reload.status?
  end

  # ---- Offer revision ----

  def hour(day, hour) = Time.utc(2030, 1, day, hour)

  test "revise_offer! adds and removes instants, deletes the guests' picks at removed instants and stamps the event" do
    @event.update_columns(revision: 2, notified_revision: 2)
    wanted = [ 11, 12, 13, 14, 15 ].map { |h| hour(15, h) }

    revision = @event.revise_offer!(starts_at: wanted)

    assert_equal 4, revision.added.size
    assert_equal [ hour(15, 10) ], revision.removed
    assert revision.delta?
    assert_not revision.no_op?
    assert_equal [], revision.trimmed_ids
    assert_equal [ @guest.id ], revision.voided_ids
    assert_equal wanted, @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
    assert_equal 0, @guest.time_slots.count
    @event.reload
    assert_in_delta Time.current, @event.offer_revised_at, 5.seconds
    assert_equal [ 4, 1, 3 ], [ @event.offer_revision_added, @event.offer_revision_removed, @event.revision ]
    assert_equal 2, @event.notified_revision, "the batch, not the model, marks guests told"
  end

  test "a trimmed guest keeps the picks that stay and keeps counting" do
    @event.replace_time_slots!(participant: @guest, starts_at: [ hour(15, 10), hour(15, 11) ])
    before = @guest.reload.attributes

    revision = @event.revise_offer!(starts_at: [ hour(15, 10) ])

    assert_equal [ @guest.id ], revision.trimmed_ids
    assert_equal [], revision.voided_ids
    assert_equal [ hour(15, 10) ], @guest.time_slots.pluck(:start_time)
    assert_equal before, @guest.reload.attributes, "nothing on a trimmed guest changes"
    assert_includes @event.participants.counting, @guest
    assert_equal [ 0, 1 ], [ @event.offer_revision_added, @event.offer_revision_removed ]
  end

  test "a guest left with nothing is voided, not reset, and other guests are untouched" do
    declined = @event.participants.create!(role: :guest, email: "declined@example.com", token_digest: "d" * 64,
      responded_at: 3.days.ago, declined_at: 3.days.ago)
    pending = participants(:planning_pending)
    left = participants(:planning_left)
    snapshot = -> { [ declined, pending, left ].map { |row| row.reload.attributes } }
    others_before = snapshot.call
    guest_before = @guest.attributes
    MailDelivery.create!(event: @event, participant: @guest, kind: :invitation, recipient_email: @guest.email)
    ledger = @guest.mail_deliveries.order(:id).pluck(:id)

    revision = @event.revise_offer!(starts_at: [ hour(15, 11) ])

    assert_equal [ @guest.id ], revision.voided_ids
    @guest.reload
    assert_in_delta Time.current, @guest.reply_voided_at, 5.seconds
    assert @guest.voided?
    assert_not @guest.counting?
    assert_equal 0, @guest.time_slots.count
    assert_not_includes @event.participants.counting, @guest
    assert_equal guest_before.except("reply_voided_at", "updated_at"), @guest.attributes.except("reply_voided_at", "updated_at")
    assert_equal ledger, @guest.mail_deliveries.order(:id).pluck(:id)
    assert_equal others_before, snapshot.call, "declined, unreplied and left guests are unchanged"
    assert_nil declined.reply_voided_at
  end

  test "revise_offer! resubmitting the current offer writes nothing" do
    @event.update_columns(revision: 2, notified_revision: 2)
    slots = @event.time_slots.order(:id).map(&:attributes)
    updated_at = @event.updated_at

    revision = @event.revise_offer!(starts_at: [ hour(15, 11), hour(15, 10), hour(15, 10) ])

    assert revision.no_op?
    assert_not revision.grid_changed
    @event.reload
    assert_equal 2, @event.revision
    assert_nil @event.offer_revised_at
    assert_equal [ 0, 0 ], [ @event.offer_revision_added, @event.offer_revision_removed ]
    assert_equal updated_at, @event.updated_at
    assert_equal slots, @event.time_slots.order(:id).map(&:attributes)
  end

  test "revise_offer! with a zone or step change and the same instants bumps the revision only" do
    berlin = plan(time_zone: "Europe/Berlin", starts_at: [ Time.utc(2031, 2, 10, 9), Time.utc(2031, 2, 10, 10) ])
    slots = berlin.time_slots.order(:id).map(&:attributes)

    revision = berlin.revise_offer!(starts_at: [ Time.utc(2031, 2, 10, 9), Time.utc(2031, 2, 10, 10) ], time_zone: "Europe/Paris")

    assert_not revision.delta?
    assert_not revision.no_op?
    assert revision.grid_changed
    berlin.reload
    assert_equal "Europe/Paris", berlin.time_zone
    assert_equal 1, berlin.revision
    assert_nil berlin.offer_revised_at
    assert_equal [ 0, 0 ], [ berlin.offer_revision_added, berlin.offer_revision_removed ]
    assert_equal slots, berlin.time_slots.order(:id).map(&:attributes)

    revision = berlin.revise_offer!(starts_at: [ Time.utc(2031, 2, 10, 9), Time.utc(2031, 2, 10, 10) ], slot_minutes: 30)
    assert revision.grid_changed
    assert_not revision.delta?
    assert_equal [ 30, 2 ], [ berlin.reload.slot_minutes, berlin.revision ]
  end

  test "revise_offer! clears a planned length that stops fitting the new step" do
    thirty = plan(slot_minutes: 30, duration_minutes: 90, starts_at: [ Time.utc(2031, 2, 10, 9), Time.utc(2031, 2, 10, 9, 30) ])

    revision = thirty.revise_offer!(starts_at: [ Time.utc(2031, 2, 10, 9) ], slot_minutes: 60)

    assert revision.duration_cleared
    assert revision.delta?
    thirty.reload
    assert_nil thirty.duration_minutes
    assert_equal 60, thirty.slot_minutes
    assert_equal [ Time.utc(2031, 2, 10, 9) ], thirty.time_slots.pluck(:start_time)

    fifteen = plan(slot_minutes: 15, duration_minutes: 90, starts_at: [ Time.utc(2031, 2, 10, 9) ])
    revision = fifteen.revise_offer!(starts_at: [ Time.utc(2031, 2, 10, 9) ], slot_minutes: 30)
    assert_not revision.duration_cleared, "90 still fits 30-minute slots"
    assert_equal 90, fifteen.reload.duration_minutes
  end

  test "revise_offer! refuses a step or zone change once a guest has replied, writing nothing" do
    error = assert_raises(ActiveRecord::RecordInvalid) { @event.revise_offer!(starts_at: [ hour(15, 10), hour(15, 11) ], slot_minutes: 30) }
    assert_match "cannot change after a guest has replied", error.message
    assert_raises(ActiveRecord::RecordInvalid) { @event.revise_offer!(starts_at: [ hour(15, 10), hour(15, 11) ], time_zone: "Asia/Kolkata") }

    @event.reload
    assert_equal [ 60, "UTC", 0 ], [ @event.slot_minutes, @event.time_zone, @event.revision ]
    assert_equal [ hour(15, 10), hour(15, 11) ], @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)

    fresh = plan(starts_at: [ Time.utc(2031, 2, 10, 9) ])
    fresh.revise_offer!(starts_at: [ Time.utc(2031, 2, 10, 4, 30), Time.utc(2031, 2, 10, 5) ], slot_minutes: 30, time_zone: "Asia/Kolkata")
    fresh.reload
    assert_equal [ 30, "Asia/Kolkata" ], [ fresh.slot_minutes, fresh.time_zone ]
    assert_equal [ Time.utc(2031, 2, 10, 4, 30), Time.utc(2031, 2, 10, 5) ], fresh.time_slots.order(:start_time).pluck(:start_time)
  end

  test "revise_offer! validates against the new grid and refuses blank input before the lock" do
    error = assert_raises(ArgumentError) { @event.revise_offer!(starts_at: [ hour(15, 10), Time.utc(2030, 1, 15, 10, 30) ]) }
    assert_equal "Select time slots on the event's 60-minute grid", error.message

    locking_queries = capture_locking_queries do
      assert_raises(ArgumentError) { @event.revise_offer!(starts_at: []) }
      assert_raises(ArgumentError) { @event.revise_offer!(starts_at: [ nil ]) }
    end
    assert_empty locking_queries
    assert_equal 0, @event.reload.revision
  end

  test "revise_offer! never touches instants before the cut-off" do
    past = 2.days.ago.utc.beginning_of_hour
    now = Time.current
    TimeSlot.insert_all!([
      { participant_id: @organizer.id, event_id: @event.id, start_time: past, created_at: now, updated_at: now },
      { participant_id: @guest.id, event_id: @event.id, start_time: past, created_at: now, updated_at: now }
    ])
    @event.time_slots.where(participant_id: @guest.id, start_time: hour(15, 10)).delete_all

    revision = @event.revise_offer!(starts_at: [ hour(15, 11), hour(15, 12) ])

    assert_equal [ hour(15, 12) ], revision.added
    assert_equal [ hour(15, 10) ], revision.removed, "the past row is not a removal"
    assert_equal [], revision.voided_ids, "a guest holding only a past pick is not voided"
    assert_equal [], revision.trimmed_ids
    assert_equal [ past, hour(15, 11), hour(15, 12) ], @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
    assert_equal [ past ], @guest.time_slots.pluck(:start_time)
    assert_nil @guest.reload.reply_voided_at
    assert_equal [ 1, 1 ], [ @event.reload.offer_revision_added, @event.offer_revision_removed ]

    same = @event.revise_offer!(starts_at: [ hour(15, 11), hour(15, 12) ])
    assert same.no_op?, "omitting the past row again is still nothing"
  end

  test "revise_offer! is refused on a finalized event with the closed message" do
    finalized = events(:finalized)
    error = assert_raises(Event::ClosedError) { finalized.revise_offer!(starts_at: [ hour(15, 12) ]) }
    assert_equal "Availability is closed for this event", error.message
    assert_equal [ hour(15, 10) ], finalized.time_slots.where(participant_id: participants(:finalized_organizer).id).pluck(:start_time)
  end

  test "the offer revision counts are a real check" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) { @event.update_columns(offer_revised_at: Time.current) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Event.transaction(requires_new: true) { @event.update_columns(offer_revision_added: 2) }
    end
    assert_nil @event.reload.offer_revised_at
  end

  test "mark_unavailable! and a new save clear the void in one statement" do
    @guest.update_columns(reply_voided_at: Time.current)

    assert_nothing_raised { @event.mark_unavailable!(participant: @guest) }
    @guest.reload
    assert @guest.declined_at.present?
    assert_nil @guest.reply_voided_at

    @guest.update_columns(declined_at: nil)
    @guest.update_columns(reply_voided_at: Time.current)
    @event.replace_time_slots!(participant: @guest, starts_at: [ hour(15, 10) ])
    @guest.update!(responded_at: Time.current, declined_at: nil, reply_voided_at: nil)
    assert @guest.reload.counting?
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
