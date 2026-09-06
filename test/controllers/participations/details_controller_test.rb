require "test_helper"

module Participations
  class DetailsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:planning)
      @organizer = participants(:planning_organizer)
      @organizer_token = raw_token(:planning_organizer)
      @guest_token = raw_token(:planning_guest)
    end

    test "a guest token is not found on edit and update, and the event is unchanged" do
      get edit_participation_details_path(@guest_token)
      assert_response :not_found
      assert_select "#link-not-found"

      patch participation_details_path(@guest_token), params: { event: { name: "Hijacked" } }
      assert_response :not_found
      assert_equal "Planning session", @event.reload.name

      sign_in users(:invitee)
      get edit_my_participation_details_path(participants(:planning_guest))
      assert_response :not_found
      patch my_participation_details_path(participants(:planning_guest)), params: { event: { name: "Hijacked" } }
      assert_response :not_found
      assert_equal "Planning session", @event.reload.name
    end

    test "the organizer edits the fields on one face; step and zone are facts" do
      @event.update_columns(slot_minutes: 30, time_zone: "Europe/Berlin")

      get edit_participation_details_path(@organizer_token)

      assert_response :success
      assert_select "#event-details .form-inputs", count: 1
      assert_select "form#details-form[action=?][method=post]", participation_details_path(@organizer_token) do
        assert_select "input[name='_method'][value=patch]"
        assert_select "input[name='event[name]'][value=?]", "Planning session"
        assert_select "textarea[name='event[description]']", text: "Pick a time that works for everyone"
        assert_select "input[name='event[place]'][maxlength='200']"
        assert_select "input[name='event[place_url]'][type=url]"
        assert_select "select#event_duration_minutes[name='event[duration_minutes]']" do
          assert_select "option[value='']", "Not set"
          assert_select "option[value='90']:not([disabled])", "1 h 30 min"
          assert_select "option[value='45'][disabled]"
        end
        assert_select "input[type=submit][value='Save details']"
      end
      assert_match "30-minute slots · Europe/Berlin", response.body
      assert_select "[name='event[slot_minutes]']", count: 0
      assert_select "[name='event[time_zone]']", count: 0
      assert_select "select#timezone-picker-show", count: 0
      assert_select "form form", count: 0
      assert_select "a[href=?]", participation_path(@organizer_token), text: "Back to the event"
      assert_select 'meta[name="robots"][content="noindex"]'
    end

    test "a finalized event shows its window in the event zone and still takes details" do
      finalized = events(:finalized)
      finalized.update_columns(time_zone: "Europe/Berlin")
      token = raw_token(:finalized_organizer)

      get edit_participation_details_path(token)

      assert_response :success
      assert_select "time[data-zoned-instant][datetime=?]", "2030-01-15T10:00:00Z", text: "Tue 15 Jan 2030 11:00 (Europe/Berlin)"
      assert_select "time[data-zoned-instant][datetime=?]", "2030-01-15T11:00:00Z", text: "12:00 (Europe/Berlin)"
      assert_select "time[data-zoned-instant]", count: 2

      patch participation_details_path(token), params: { event: { name: "Finalized event", description: finalized.description, place: "Zoom", place_url: "https://zoom.us/j/1", duration_minutes: "" } }

      assert_response :see_other
      assert_redirected_to participation_path(token)
      assert_equal "Details saved.", flash[:notice]
      finalized.reload
      assert_equal "Zoom", finalized.place
      assert_equal "https://zoom.us/j/1", finalized.place_url
      assert_equal 1, finalized.revision
      assert finalized.status?
    end

    test "the organizer saves details through either family and posted step and zone are ignored" do
      patch participation_details_path(@organizer_token), params: { event: {
        name: "  Planning   session ", description: "Pick a time", place: " Ege's place ", place_url: "HTTPS://zoom.us/j/1",
        duration_minutes: "120", slot_minutes: "15", time_zone: "Asia/Kolkata"
      } }

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Details saved.", flash[:notice]
      @event.reload
      assert_equal "Ege's place", @event.place
      assert_equal "https://zoom.us/j/1", @event.place_url
      assert_equal 120, @event.duration_minutes
      assert_equal 60, @event.slot_minutes
      assert_equal "UTC", @event.time_zone
      assert_equal 1, @event.revision

      sign_in users(:owner)
      get edit_my_participation_details_path(@organizer)
      assert_response :success
      assert_select "form#details-form[action=?]", my_participation_details_path(@organizer)
      assert_select "input[name='event[place_url]'][value=?]", "https://zoom.us/j/1"
      assert_select "select#event_duration_minutes option[value='120'][selected]"

      patch my_participation_details_path(@organizer), params: { event: { name: "Planning session", description: "Pick a time", place: "Ege's flat", place_url: "", duration_minutes: "" } }
      assert_redirected_to my_participation_path(@organizer)
      assert_response :see_other
      @event.reload
      assert_equal "Ege's flat", @event.place
      assert_nil @event.place_url
      assert_nil @event.duration_minutes
      assert_equal 2, @event.revision
    end

    test "an invalid link re-renders the face with 422 and changes nothing" do
      patch participation_details_path(@organizer_token), params: { event: { name: "Planning session", description: "Pick a time that works for everyone", place_url: "ftp://files.example" } }

      assert_response :unprocessable_entity
      assert_select "input[name='event[place_url]'].is-invalid[value=?]", "ftp://files.example"
      assert_select ".invalid-feedback", text: "must be a web address starting with http:// or https://"
      assert_select "form form", count: 0
      @event.reload
      assert_nil @event.place_url
      assert_equal 0, @event.revision

      patch participation_details_path(@organizer_token), params: { event: { name: "", description: "x", duration_minutes: "45" } }
      assert_response :unprocessable_entity
      assert_select ".invalid-feedback", text: "can't be blank"
      assert_select ".invalid-feedback", text: "must be a whole number of 60-minute slots"
      assert_equal "Planning session", @event.reload.name
    end

    test "a cancelled event refuses edit and update with one alert" do
      @event.update_columns(cancelled_at: Time.current)

      get edit_participation_details_path(@organizer_token)
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]

      patch participation_details_path(@organizer_token), params: { event: { name: "Renamed" } }
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      assert_equal "Planning session", @event.reload.name
    end

    test "the details page is not cached and needs no session through the token family" do
      get edit_participation_details_path(@organizer_token)

      assert_equal "no-store", response.headers["Cache-Control"]

      get edit_my_participation_details_path(@organizer)
      assert_redirected_to new_user_session_path
    end
  end
end
