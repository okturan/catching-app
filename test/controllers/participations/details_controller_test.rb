require "test_helper"

module Participations
  class DetailsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionMailer::TestCase::ClearTestDeliveries

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

    test "the plan editor gives every item its own form and labelled controls, and no form nests" do
      board = activities(:planning_activity)
      dune = @event.activities.create!(name: "Dune", duration: 155, position: 1, description: "Part one")

      get edit_participation_details_path(@organizer_token)

      assert_response :success
      assert_select "#event-details .form-inputs .plan-editor", count: 1 do
        assert_select "h2", text: "The plan"
        assert_select "ol.plan-items li.plan-item", count: 2
        assert_select "li.plan-item:nth-child(1) .plan-item-head", text: /1\. Board games · 1 h 30 min/
        assert_select "li.plan-item:nth-child(2) .plan-item-head", text: /2\. Dune · 2 h 35 min/
        assert_select "form.plan-item-form", count: 2
        assert_select "form.plan-item-form[action=?][method=post][aria-label=?]", participation_activity_path(@organizer_token, board), "Edit Board games" do
          assert_select "input[name='_method'][value=patch]"
          assert_select "input[name='activity[name]'][value=?][maxlength='80'][required]", "Board games"
          assert_select "label[for=?]", "plan_#{board.id}_activity_name", text: "Name"
          assert_select "select[name='activity[duration]']" do
            assert_select "option[value='']", "No length"
            assert_select "option[value='90'][selected]", "1 h 30 min"
            assert_select "option", count: 10
          end
          assert_select "input[name='activity[description]'][value=?][maxlength='500']", "Play a cooperative game"
          assert_select "input[type=submit][value=Save][aria-label=?]", "Save Board games"
        end
        assert_select "form.plan-item-form[action=?]", participation_activity_path(@organizer_token, dune) do
          assert_select "select[name='activity[duration]'] option[value='155'][selected]", "2 h 35 min"
          assert_select "select[name='activity[duration]'] option", count: 11
        end
        assert_select "button[aria-label=?]", "Move Board games up", text: "Up"
        assert_select "button[aria-label=?]", "Move Board games down", text: "Down"
        assert_select "button[aria-label=?]", "Remove Board games", text: "Remove"
        assert_select "form[action=?]", participation_activity_move_path(@organizer_token, board), count: 2
        assert_select "form[action=?] input[name='move[position]'][value='-1']", participation_activity_move_path(@organizer_token, board)
        assert_select "form[action=?] input[name='move[position]'][value='1']", participation_activity_move_path(@organizer_token, board)
        assert_select "form[action=?] input[name='move[position]'][value='0']", participation_activity_move_path(@organizer_token, dune)
        assert_select "form[action=?][data-turbo-confirm=?]", participation_activity_path(@organizer_token, board), "Remove Board games from the plan?" do
          assert_select "input[name='_method'][value=delete]"
          assert_select "button[type=submit]", text: "Remove"
        end
        assert_select "form#plan-add-form[action=?][method=post]", participation_activities_path(@organizer_token) do
          assert_select "input[name='_method']", count: 0
          assert_select "label[for=activity_name]", text: "Add to the plan"
          assert_select "input#activity_name[name='activity[name]'][required][maxlength='80']"
          assert_select "label[for=activity_duration]", text: "Length"
          assert_select "select#activity_duration[name='activity[duration]']" do
            assert_select "option[value='']", "No length"
            assert_select "option[value='15']", "15 min"
            assert_select "option[value='240']", "4 h"
            assert_select "option", count: 10
          end
          assert_select "label[for=activity_description]", text: "Description"
          assert_select "input#activity_description[name='activity[description]'][maxlength='500']"
          assert_select "input[type=submit][value=?]", "Add to the plan"
        end
        assert_select "time[data-zoned-instant]", count: 0
        assert_select ".plan-note", count: 0
      end
      assert_select "form form", count: 0
      assert_select "form#details-form input[name^='activity']", count: 0
    end

    test "an empty plan says so and the editor still offers the add row" do
      @event.activities.delete_all

      get edit_participation_details_path(@organizer_token)

      assert_select ".plan-editor .plan-empty", text: /Nothing planned yet/
      assert_select ".plan-editor li.plan-item", count: 0
      assert_select "form#plan-add-form"
    end

    test "once the time is set the editor shows derived starts and says when the plan outruns the window" do
      finalized = events(:finalized)
      finalized.update_columns(end_time: Time.utc(2030, 1, 15, 12))
      pizza = finalized.activities.create!(name: "Pizza", duration: 30, position: 0)
      movie = finalized.activities.create!(name: "The movie", duration: 120, position: 1)
      token = raw_token(:finalized_organizer)

      get edit_participation_details_path(token)

      assert_response :success
      assert_select ".plan-editor .plan-note", text: "The plan runs 2 h 30 min; the set time is 2 h."
      assert_select "li#plan-item-#{pizza.id} .plan-item-head time.time[data-zoned-instant][datetime=?]", "2030-01-15T10:00:00Z", text: "10:00 (UTC)"
      assert_select "li#plan-item-#{movie.id} .plan-item-head time.time[data-zoned-instant][datetime=?]", "2030-01-15T10:30:00Z", text: "10:30 (UTC)"

      movie.update!(duration: 60)
      get edit_participation_details_path(token)
      assert_select ".plan-note", count: 0
      assert_no_match "The plan runs", response.body
    end

    test "the notice checkbox is offered only to an opened organizer with linked guests, unchecked while pending and checked once set" do
      get edit_participation_details_path(@organizer_token)
      assert_response :success
      assert_select "form#details-form input#notice_send[type=checkbox][name='notice[send]'][value='1']", count: 1
      assert_select "input#notice_send[checked]", count: 0
      assert_select "label[for=notice_send]", text: "Email the guests about this change"

      get edit_participation_details_path(raw_token(:finalized_organizer))
      assert_select "input#notice_send[checked]", count: 1

      @organizer.update_columns(link_opened_at: nil)
      get edit_participation_details_path(@organizer_token)
      assert_response :success
      assert_select "[name='notice[send]']", count: 0

      @organizer.update_columns(link_opened_at: Time.current)
      @event.guests.update_all(token_digest: nil)
      get edit_participation_details_path(@organizer_token)
      assert_select "[name='notice[send]']", count: 0
    end

    test "a ticked notice mails the guests about a real change and reports the count; an unticked or empty save sends nothing" do
      assert_no_difference "MailDelivery.count" do
        patch participation_details_path(@organizer_token), params: { event: { place: "Zoom" } }
      end
      assert_equal "Details saved.", flash[:notice]
      assert_equal "Zoom", @event.reload.place

      assert_no_difference "MailDelivery.count" do
        patch participation_details_path(@organizer_token), params: { event: { place: "Zoom" }, notice: { send: "1" } }
      end
      assert_equal "Details saved.", flash[:notice]
      assert_equal 1, @event.reload.revision

      assert_difference "MailDelivery.event_updated.count", 2 do
        perform_enqueued_jobs do
          patch participation_details_path(@organizer_token), params: { event: { name: "Dune night", place: "Ege's place" }, notice: { send: "1" } }
        end
      end
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Details saved. 2 guests emailed.", flash[:notice]
      @event.reload
      assert_equal 2, @event.revision
      assert_equal 2, @event.notified_revision
      mails = ActionMailer::Base.deliveries.last(2)
      assert_equal %w[invitee@example.com pending@example.com], mails.flat_map(&:to).sort
      mails.each do |mail|
        assert_equal "Catching App: Olivia Owner changed Dune night", mail.subject
        body = mail.text_part.body.to_s
        assert_includes body, "Olivia Owner changed the details of Dune night."
        assert_includes body, "The event is now called Dune night (was Planning session)"
        assert_includes body, "Where: Ege's place"
      end

      assert_no_difference "MailDelivery.count" do
        patch participation_details_path(@organizer_token), params: { event: { place: "Kadıköy" }, notice: { send: "1" } }
      end
      assert_equal "Details saved. 0 guests emailed. 2 skipped (recently notified). Try again after 10 minutes.", flash[:notice]
      assert_equal "Kadıköy", @event.reload.place
      assert_equal 3, @event.revision
      assert_equal 2, @event.notified_revision, "nothing reached the guests this time"
    end

    test "a ticked notice from an organizer who never opened the link saves the details and answers the hint" do
      @organizer.update_columns(link_opened_at: nil)

      assert_no_difference "MailDelivery.count" do
        patch participation_details_path(@organizer_token), params: { event: { place: "Zoom" }, notice: { send: "1" } }
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Details saved.", flash[:notice]
      assert_equal "Open your organizer link before emailing guests", flash[:alert]
      assert_equal "Zoom", @event.reload.place
    end

    test "the details page is not cached and needs no session through the token family" do
      get edit_participation_details_path(@organizer_token)

      assert_equal "no-store", response.headers["Cache-Control"]

      get edit_my_participation_details_path(@organizer)
      assert_redirected_to new_user_session_path
    end
  end
end
