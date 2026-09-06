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
      organizer: { name: "Ann Organizer", email: "Ann@example.com" },
      invitations: { emails: "Bob@example.com\ncy@example.com, ann@example.com" },
      time_slots: { time_slot_array: @slots.map(&:iso8601).join(",") }
    }.deep_merge(overrides)
  end

  test "the new form is public and has the planning fields and no member directory" do
    get new_event_path

    assert_response :success
    assert_select "input[name='organizer[name]']"
    assert_select "input[name='organizer[email]']"
    assert_select "select#event_slot_minutes option[selected][value='30']"
    assert_select "textarea[name='invitations[emails]']", count: 0
    assert_select "select#timezone-picker-new[name='event[time_zone]']"
    assert_select "select[name='event[invited_user_ids][]']", count: 0
    assert_select "table#time-grid-define[data-slot-minutes='30']"
    assert_select "input[name='event[place]'][maxlength='200'][placeholder=?]", "Ege's place, Kadıköy — or 'Zoom'"
    assert_select "input[name='event[place_url]'][type=url][placeholder=?]", "Link to join or a map link"
    assert_select "select#event_duration_minutes[name='event[duration_minutes]']" do
      assert_select "option", count: 22
      assert_select "option[value='']", "Not set"
      assert_select "option[value='30']:not([disabled])", "30 min"
      assert_select "option[value='90']:not([disabled])", "1 h 30 min"
      assert_select "option[value='45'][disabled]", "45 min"
      assert_select "option[value='240']:not([disabled])", "4 h"
      assert_select "option[value='1440']:not([disabled])", "24 h"
      assert_select "option[selected]", count: 0
    end
    values = css_select("select#event_duration_minutes option").map { |option| option["value"] }.reject(&:empty?).map(&:to_i)
    assert_equal (15..240).step(15).to_a + [ 300, 360, 480, 720, 1440 ], values
    disabled = css_select("select#event_duration_minutes option[disabled]").map { |option| option["value"].to_i }
    assert_equal values.reject { |minutes| (minutes % 30).zero? }, disabled

    sign_in @owner
    get new_event_path
    assert_select "input[name='organizer[email]']", count: 0
  end

  test "an anonymous organizer plans an event and gets only the organizer link" do
    assert_difference({ "Event.count" => 1, "Participant.count" => 3, "TimeSlot.count" => 2, "MailDelivery.organizer_link.count" => 1 }) do
      assert_enqueued_emails 1 do
        post events_path, params: valid_params
      end
    end

    event = Event.order(:id).last
    organizer = event.organizer
    assert_redirected_to pending_events_path
    assert_equal "ann@example.com", organizer.email
    assert_equal "Ann Organizer", organizer.name
    assert_nil organizer.user
    assert_nil organizer.link_opened_at
    assert organizer.token_digest.present?
    assert_equal %w[bob@example.com cy@example.com], event.guests.order(:email).pluck(:email)
    assert event.guests.all? { |guest| guest.token_digest.nil? }
    assert_equal 0, MailDelivery.invitation.count
    assert_equal @slots.map(&:utc), event.time_slots.where(participant_id: organizer.id).order(:start_time).pluck(:start_time)

    follow_redirect!
    assert_match "ann@example.com", response.body
    assert_match "Nothing has gone to your guests yet", response.body
  end

  test "place, link and planned length are saved with the plan and echoed on a 422" do
    facts = { place: "  Ege's   place ", place_url: "HTTPS://zoom.us/j/1", duration_minutes: "90" }

    post events_path, params: valid_params(event: facts)

    event = Event.order(:id).last
    assert_redirected_to pending_events_path
    assert_equal "Ege's place", event.place
    assert_equal "https://zoom.us/j/1", event.place_url
    assert_equal 90, event.duration_minutes

    post events_path, params: valid_params(event: { place: "Ege's place", place_url: "https://zoom.us/j/1", duration_minutes: "90" }, time_slots: { time_slot_array: "" })

    assert_response :unprocessable_entity
    assert_select "input[name='event[place]'][value=?]", "Ege's place"
    assert_select "input[name='event[place_url]'][value=?]", "https://zoom.us/j/1"
    assert_select "select#event_duration_minutes option[value='90'][selected]"

    post events_path, params: valid_params(event: { place_url: "javascript:alert(1)", duration_minutes: "45" })
    assert_response :unprocessable_entity
    assert_match "must be a web address starting with http:// or https://", response.body
    assert_match "must be a whole number of 30-minute slots", response.body
  end

  test "a signed-in organizer is claimed and cannot override the email" do
    sign_in @owner

    post events_path, params: valid_params(organizer: { email: "other@example.com", name: "Other" })

    organizer = Event.order(:id).last.organizer
    assert_equal "owner@example.com", organizer.email
    assert_equal "Olivia Owner", organizer.name
    assert_equal @owner, organizer.user
    assert_nil organizer.link_opened_at
    assert_redirected_to pending_events_path
  end

  test "invalid availability rolls back the complete plan and echoes the form" do
    assert_no_difference [ "Event.count", "Participant.count", "TimeSlot.count", "MailDelivery.count" ] do
      post events_path, params: valid_params(time_slots: { time_slot_array: "not-an-iso8601-time" })
    end

    assert_response :unprocessable_entity
    assert_select "input[name='organizer[email]'][value='ann@example.com']"
    assert_select "select#timezone-picker-new[data-selected='Europe/Berlin']"
    assert_select "#time_slot_array[value='not-an-iso8601-time']"
    assert_match "Time slots must use ISO 8601 timestamps", response.body
  end

  test "empty availability, unknown zones, bad addresses and a missing organizer are validation errors" do
    post events_path, params: valid_params(time_slots: { time_slot_array: "" })
    assert_response :unprocessable_entity
    assert_match "Select at least one time slot", response.body

    post events_path, params: valid_params(event: { time_zone: "Mars/Olympus" })
    assert_response :unprocessable_entity
    assert_match "is not a known time zone", response.body

    post events_path, params: valid_params(invitations: { emails: "nope" })
    assert_response :unprocessable_entity
    assert_match "nope is not a valid email address", response.body

    post events_path, params: valid_params(organizer: { name: "", email: "not-an-address" })
    assert_response :unprocessable_entity
    assert_no_difference("Event.count") { }
  end

  test "a 422 lists every error once, linked to the control that raised it" do
    post events_path, params: valid_params(event: { time_zone: "Mars/Olympus", place_url: "javascript:alert(1)", duration_minutes: "45" })

    assert_response :unprocessable_entity
    assert_select "#error-summary[role=alert][tabindex='-1']" do
      assert_select "li", count: 3
      assert_select "a[href='#timezone-picker-new']", text: "Time zone is not a known time zone"
      assert_select "a[href='#event_place_url']", text: "Link must be a web address starting with http:// or https://"
      assert_select "a[href='#event_duration_minutes']", text: "Planned length must be a whole number of 30-minute slots"
    end
    # The rescue no longer appends the exception on top of the record's own
    # errors, so the summary and the field's own message are the only copies.
    assert_equal 2, response.body.scan("must be a web address starting with http:// or https://").size
    assert_select "#event_place_url[aria-invalid=true][aria-describedby=?]", "event_place_url_help event_place_url_error"

    post events_path, params: valid_params(time_slots: { time_slot_array: "" })
    assert_select "#error-summary li a[href='#time-grid-define']", text: "Select at least one time slot"

    post events_path, params: valid_params(organizer: { name: "", email: "not-an-address" })
    assert_select "#error-summary li a[href='#organizer_name']", text: "Your name can't be blank"
    assert_select "#error-summary li a[href='#organizer_email']", text: "Your email is invalid"
    assert_select "input#organizer_email.is-invalid[aria-invalid=true][aria-describedby=?]", "organizer_email_help organizer_email_error"
    assert_select "#organizer_email_error", text: "is invalid"
  end

  test "creation caps refuse with one generic message for known and unknown addresses" do
    responses = [ "owner@example.com", "nobody@example.com" ].map do |email|
      3.times do
        post events_path, params: valid_params(organizer: { email: email, name: "Repeat" }), headers: { "REMOTE_ADDR" => "203.0.113.10" }
        assert_response :redirect
      end
      post events_path, params: valid_params(organizer: { email: email, name: "Repeat" }), headers: { "REMOTE_ADDR" => "203.0.113.10" }
      [ response.status, response.location, flash[:alert] ]
    end

    assert_equal 1, responses.uniq.size
    assert_equal [ 303, new_event_url, MailDelivery::Caps::CREATION_MESSAGE ], responses.first
  end

  test "a third party cannot exhaust a victim's allowance from another network" do
    3.times do
      post events_path, params: valid_params(organizer: { email: "victim@example.com", name: "Attacker" }), headers: { "REMOTE_ADDR" => "203.0.113.11" }
    end

    post events_path, params: valid_params(organizer: { email: "victim@example.com", name: "Victim" }), headers: { "REMOTE_ADDR" => "198.51.100.44" }

    assert_redirected_to pending_events_path
  end

  test "creation is rate limited per IP as a courtesy" do
    with_rate_limit_count(6) do
      post events_path, params: valid_params
    end

    assert_response :too_many_requests
  end

  test "legacy event routes no longer exist" do
    sign_in @owner

    get "/events/#{events(:planning).id}"
    assert_response :not_found
  end
end
