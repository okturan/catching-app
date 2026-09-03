require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:owner)
    @berlin = ActiveSupport::TimeZone["Europe/Berlin"]
    @slots = [ @berlin.local(2031, 2, 10, 9, 0), @berlin.local(2031, 2, 10, 9, 30) ]
  end

  def valid_params(overrides = {})
    {
      event: { name: "Project kickoff", description: "Find a kickoff time", slot_minutes: 30, time_zone: "Europe/Berlin" },
      invitations: { emails: "Bob@example.com\ncy@example.com, owner@example.com" },
      time_slots: { time_slot_array: @slots.map(&:iso8601).join(",") }
    }.deep_merge(overrides)
  end

  test "the new form has the planning fields and no member directory" do
    sign_in @owner

    get new_event_path

    assert_response :success
    assert_select "select#event_slot_minutes option[selected][value='30']"
    assert_select "textarea[name='invitations[emails]']"
    assert_select "select#timezone-picker-new[name='event[time_zone]']"
    assert_select "select[name='event[invited_user_ids][]']", count: 0
    assert_select "table#time-grid-define[data-slot-minutes='30']"
  end

  test "planning creates the event, organizer, offer and guests atomically" do
    sign_in @owner

    assert_difference({ "Event.count" => 1, "Participant.count" => 3, "TimeSlot.count" => 2 }) do
      post events_path, params: valid_params
    end

    event = Event.order(:id).last
    organizer = event.organizer
    assert_redirected_to my_participation_path(organizer)
    assert_equal @owner, organizer.user
    assert organizer.link_opened_at.present?
    assert organizer.token_digest.present?
    assert_equal %w[bob@example.com cy@example.com], event.guests.order(:email).pluck(:email)
    assert_equal @slots.map(&:utc), event.time_slots.where(participant_id: organizer.id).order(:start_time).pluck(:start_time)
    assert_equal 30, event.slot_minutes
  end

  test "invalid availability rolls back the complete plan and echoes the form" do
    sign_in @owner

    assert_no_difference [ "Event.count", "Participant.count", "TimeSlot.count" ] do
      post events_path, params: valid_params(time_slots: { time_slot_array: "not-an-iso8601-time" })
    end

    assert_response :unprocessable_entity
    assert_select "textarea[name='invitations[emails]']", text: /cy@example.com/
    assert_select "select#timezone-picker-new[data-selected='Europe/Berlin']"
    assert_select "#time_slot_array[value='not-an-iso8601-time']"
    assert_match "Time slots must use ISO 8601 timestamps", response.body
  end

  test "empty availability, unknown zones and bad addresses are validation errors" do
    sign_in @owner

    post events_path, params: valid_params(time_slots: { time_slot_array: "" })
    assert_response :unprocessable_entity
    assert_match "Select at least one time slot", response.body

    post events_path, params: valid_params(event: { time_zone: "Mars/Olympus" })
    assert_response :unprocessable_entity
    assert_match "is not a known time zone", response.body

    post events_path, params: valid_params(invitations: { emails: "nope" })
    assert_response :unprocessable_entity
    assert_match "nope is not a valid email address", response.body
  end

  test "planning requires a session in this phase" do
    get new_event_path

    assert_redirected_to new_user_session_path
  end

  test "legacy event routes no longer exist" do
    sign_in @owner

    get "/events/#{events(:planning).id}"
    assert_response :not_found
  end
end
