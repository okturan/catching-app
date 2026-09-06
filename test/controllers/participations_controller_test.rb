require "test_helper"

class ParticipationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:planning)
    @guest = participants(:planning_guest)
    @organizer = participants(:planning_organizer)
    @guest_token = raw_token(:planning_guest)
    @organizer_token = raw_token(:planning_organizer)
  end

  test "a guest link renders the show contract without a session" do
    get participation_path(@guest_token)

    assert_response :success
    assert_select 'table#time-grid-show[role=grid][data-role=guest][data-slot-minutes="60"][data-event-time-zone="UTC"]'
    assert_select "#received-time-slots[value=?]", [ "2030-01-15T10:00:00Z", "2030-01-15T11:00:00Z" ].to_json
    assert_select "#my-time-slots[value=?]", [ "2030-01-15T10:00:00Z" ].to_json
    assert_select "#availability-counts"
    assert_select "form#availability-form[action=?]", participation_path(@guest_token)
    assert_select "button[form=availability-form]", "Save"
    assert_select "a[href=?]", participation_claim_path(@guest_token), count: 0, text: "Keep this event in your account"
    assert_no_match "pending@example.com", response.body
  end

  test "capability pages carry cache, index and canonical hygiene" do
    get participation_path(@guest_token)

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select 'meta[name="robots"][content="noindex"]'
    assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
    assert_select 'meta[property="og:url"][content=?]', root_url
  end

  test "unknown, short and left tokens are one friendly 404" do
    [ "b" * 32, "short", raw_token(:planning_left) ].each do |token|
      get participation_path(token)
      assert_response :not_found
      assert_select "#link-not-found a[href=?]", new_organizer_link_path
    end
  end

  test "a mangled link is sent to its canonical path" do
    get "/p/#{@guest_token}."

    assert_response :see_other
    assert_redirected_to participation_path(@guest_token)
  end

  test "a guest saves availability and the first reply is recorded" do
    patch participation_path(@guest_token), params: {
      time_slots: { time_slot_array: "2030-01-15T11:00:00Z" },
      participant: { name: "  Ian   Invitee ", time_zone: "Europe/Berlin" }
    }

    assert_redirected_to participation_path(@guest_token)
    assert_equal "Availability saved.", flash[:notice]
    assert_equal [ Time.utc(2030, 1, 15, 11) ], @guest.time_slots.reload.pluck(:start_time)
    assert_equal "Europe/Berlin", @guest.reload.time_zone
    assert_equal "Ian Invitee", @guest.name
    assert_equal [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ],
      @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
  end

  test "guest save errors redirect with the exact message and change nothing" do
    existing = @guest.time_slots.order(:start_time).pluck(:start_time)

    cases = {
      "" => "Select at least one time slot",
      "2030-01-20T09:00:00Z" => "Select only time slots offered by the organizer",
      "2030-01-15T10:30:00Z" => "Select time slots on the event's 60-minute grid",
      "invalid" => "Time slots must use ISO 8601 timestamps"
    }
    cases.each do |value, message|
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: value } }
      assert_response :see_other
      assert_equal message, flash[:alert], "for #{value.inspect}"
    end

    patch participation_path(@guest_token), params: {
      time_slots: { time_slot_array: "2030-01-15T10:00:00Z" }, participant: { time_zone: "Mars/Olympus" }
    }
    assert_response :see_other
    assert_match(/time zone/i, flash[:alert])

    assert_equal existing, @guest.time_slots.reload.order(:start_time).pluck(:start_time)
  end

  test "a finalized event refuses guest writes" do
    patch participation_path(raw_token(:finalized_guest)), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }

    assert_response :see_other
    assert_equal "Availability is closed for this event", flash[:alert]
  end

  test "an organizer token cannot use guest actions" do
    offer = @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)

    patch participation_path(@organizer_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_response :not_found
    post participation_decline_path(@organizer_token)
    assert_response :not_found
    delete participation_path(@organizer_token)
    assert_response :not_found

    assert_equal offer, @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
  end

  test "a guest declines and can change their mind" do
    post participation_decline_path(@guest_token), params: { participant: { time_zone: "Asia/Tokyo" } }

    assert_redirected_to participation_path(@guest_token)
    @guest.reload
    assert @guest.declined_at.present?
    assert_equal 0, @guest.time_slots.count
    assert_equal "Asia/Tokyo", @guest.time_zone
    assert_empty @event.mutually_available_start_times

    patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_nil @guest.reload.declined_at
  end

  test "a guest leaves for good" do
    delete participation_path(@guest_token)

    assert_redirected_to root_path
    assert_response :see_other
    assert_equal "You left Planning session.", flash[:notice]
    @guest.reload
    assert @guest.left_at.present?
    assert_nil @guest.user_id
    assert_nil @guest.token_digest

    get participation_path(@guest_token)
    assert_response :not_found

    sign_in users(:invitee)
    get my_participation_path(@guest)
    assert_response :not_found
  end

  test "a pending token changes nothing on GET and is promoted by its first write" do
    pending = @guest.issue_pending_token!

    get participation_path(pending)
    assert_response :success
    get participation_path(@guest_token)
    assert_response :success
    assert_equal Participant.digest(@guest_token), @guest.reload.token_digest
    assert_equal users(:invitee).id, @guest.user_id

    patch participation_path(pending), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_redirected_to participation_path(pending)
    @guest.reload
    assert_equal Participant.digest(pending), @guest.token_digest
    assert_nil @guest.pending_token_digest
    assert_nil @guest.user_id, "a write by someone who is not the claimant clears the claim"

    get participation_path(@guest_token)
    assert_response :not_found
  end

  test "promotion by the claiming account keeps the claim" do
    pending = @guest.issue_pending_token!
    sign_in users(:invitee)

    patch participation_path(pending), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }

    assert_equal users(:invitee).id, @guest.reload.user_id
  end

  test "the session family needs a session, ignores query tokens and hides other accounts" do
    get my_participation_path(@guest)
    assert_redirected_to new_user_session_path

    get my_participation_path(@guest, token: @guest_token)
    assert_redirected_to new_user_session_path

    patch my_participation_path(@guest), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_redirected_to new_user_session_path

    sign_in users(:outsider)
    get my_participation_path(@guest)
    assert_response :not_found

    sign_in users(:invitee)
    get my_participation_path(@guest)
    assert_response :success
    assert_select "form#availability-form[action=?]", my_participation_path(@guest)
    assert_select "a[href=?]", event_activities_path(@event)

    patch my_participation_path(@guest), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
    assert_redirected_to my_participation_path(@guest)
    assert_equal [ Time.utc(2030, 1, 15, 11) ], @guest.time_slots.reload.pluck(:start_time)
  end

  test "the token family ignores a participation_id query parameter" do
    get participation_path(@guest_token, participation_id: participants(:other_organizer).id)

    assert_response :success
    assert_select "table#time-grid-show[data-role=guest]"
  end

  test "the organizer link is opened only through the token family" do
    event = Event.plan!(
      attributes: { name: "Fresh", description: "new", slot_minutes: 30, time_zone: "UTC" },
      organizer: { email: users(:owner).email, name: users(:owner).full_name, user: users(:owner) },
      starts_at: [ Time.utc(2031, 5, 1, 9) ],
      invitee_emails: [ "someone@example.com" ]
    )
    organizer = event.organizer
    live = organizer.issue_live_token!

    sign_in users(:owner)
    get my_participation_path(organizer)
    assert_response :success
    assert_nil organizer.reload.link_opened_at
    assert_select "input[type=submit][value^=Send]", count: 0
    assert_match "Open the organizer link we emailed to owner@example.com", response.body

    post my_participation_invitations_path(organizer)
    assert_response :see_other
    assert_match(/Open the organizer link/, flash[:alert])
    assert_nil event.guests.first.reload.token_digest

    get participation_path(live)
    assert_response :success
    assert organizer.reload.link_opened_at.present?
    assert_select "input[type=submit][value=?]", "Send 1 invitation"
  end

  test "raw tokens never reach the request log" do
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)
    begin
      get participation_path(@guest_token)
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "invalid" } }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_match "/p/[FILTERED]", io.string
    assert_no_match @guest_token, io.string
  end

  test "writes through one token are rate limited as a courtesy" do
    with_rate_limit_count(31) do
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    end

    assert_response :too_many_requests
  end
end
