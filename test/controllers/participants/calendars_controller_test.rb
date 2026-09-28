require "test_helper"

module Participants
  class CalendarsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:finalized)
      @guest = participants(:finalized_guest)
      @guest_token = raw_token(:finalized_guest)
      @organizer_token = raw_token(:finalized_organizer)
    end

    def without_stamp(body)
      body.gsub(/^DTSTAMP:.*\r\n/, "")
    end

    # The bad-link page differs per request only in its CSRF token and the
    # og:url meta, which echoes the request URL.
    def normalized(body)
      body.gsub(/<meta name="csrf-token" content="[^"]*"/, "").gsub(/<meta property="og:url" content="[^"]*"/, "")
    end

    test "a guest downloads the page-mode file through a link" do
      @event.update!(name: "Pizza & Movie Night", place: "Ege's place", place_url: "https://zoom.us/j/1")

      get participant_calendar_path(@guest_token)

      assert_response :success
      assert_equal "/p/#{@guest_token}/calendar.ics", participant_calendar_path(@guest_token)
      assert_equal "text/calendar; charset=utf-8", response.headers["Content-Type"]
      assert_match(/\Aattachment; filename="pizza-movie-night\.ics"/, response.headers["Content-Disposition"])
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_includes response.body, "BEGIN:VCALENDAR\r\n"
      assert_includes response.body, "DTSTART:20300115T100000Z\r\n"
      assert_includes response.body, "STATUS:CONFIRMED\r\n"
      assert_includes response.body, "URL:https://zoom.us/j/1\r\n"
      assert_includes response.body, "LOCATION:Ege's place\r\n"
      assert_includes response.body, "SEQUENCE:#{@event.reload.revision}\r\n"
      assert_not_includes response.body, @guest_token
    end

    test "the account and the organizer get the same file" do
      get participant_calendar_path(@guest_token)
      token_body = without_stamp(response.body)

      sign_in users(:invitee)
      get participant_calendar_path(@guest)
      assert_response :success
      assert_equal "text/calendar; charset=utf-8", response.headers["Content-Type"]
      assert_match(/\Aattachment; filename="finalized-event\.ics"/, response.headers["Content-Disposition"])
      assert_equal token_body, without_stamp(response.body)

      get participant_calendar_path(@organizer_token)
      assert_response :success
      assert_equal token_body, without_stamp(response.body)
    end

    test "the filename falls back when the name parameterizes to nothing" do
      @event.update_columns(name: "!!!")

      get participant_calendar_path(@guest_token)

      assert_response :success
      assert_match(/\Aattachment; filename="event\.ics"/, response.headers["Content-Disposition"])
    end

    test "a pending event answers the uniform 404 through a link or the account" do
      get participant_path("b" * 32)
      not_found_page = normalized(response.body)

      get participant_calendar_path(raw_token(:planning_guest))
      assert_response :not_found
      assert_select "#link-not-found"
      assert_equal not_found_page, normalized(response.body)

      sign_in users(:invitee)
      get participant_calendar_path(participants(:planning_guest))
      assert_response :not_found
      assert_select "#link-not-found"
    end

    test "another event's token, an outsider and a mangled token get no data" do
      get participant_calendar_path(raw_token(:other_organizer))
      assert_response :not_found
      assert_no_match "Finalized event", response.body

      sign_in users(:outsider)
      get participant_calendar_path(@guest)
      assert_response :not_found
      assert_no_match "Finalized event", response.body

      get "/p/#{@guest_token}./calendar.ics"
      assert_response :see_other
      assert_redirected_to participant_calendar_path(@guest_token)
    end

    test "a cancelled finalized event serves the cancelled file with the same UID and a higher SEQUENCE" do
      get participant_calendar_path(@guest_token)
      before = response.body
      uid = before[/^UID:.*$/]
      sequence = before[/^SEQUENCE:(\d+)/, 1].to_i

      @event.cancel!
      get participant_calendar_path(@guest_token)

      assert_response :success
      assert_includes response.body, "STATUS:CANCELLED\r\n"
      assert_includes response.body, uid
      assert_includes response.body, "SEQUENCE:#{sequence + 1}\r\n"
      assert_not_includes before, "CANCELLED"
    end

    test "a cancelled pending event answers 404" do
      events(:planning).cancel!

      get participant_calendar_path(raw_token(:planning_guest))

      assert_response :not_found
      assert_select "#link-not-found"
    end

    test "the finalized page offers Add to calendar to everyone through a link or the account and the cancelled page does not" do
      get participant_path(@guest_token)
      assert_select ".event-panel .event-actions a.plate-button-sm[href=?][data-turbo=false]", participant_calendar_path(@guest_token), text: "Add to calendar"

      get participant_path(@organizer_token)
      assert_select ".event-actions a.plate-button-sm[href=?]", participant_calendar_path(@organizer_token), text: "Add to calendar"
      assert_select ".event-actions a.plate-button-sm[href=?]", edit_participant_details_path(@organizer_token), text: "Edit details"

      sign_in users(:invitee)
      get participant_path(@guest)
      assert_select "a.plate-button-sm[href=?]", participant_calendar_path(@guest), text: "Add to calendar"

      get participant_path(raw_token(:planning_guest))
      assert_select "a", text: "Add to calendar", count: 0
      assert_select ".event-actions", count: 0

      @event.cancel!
      get participant_path(@guest_token)
      assert_select "a", text: "Add to calendar", count: 0
    end
  end
end
