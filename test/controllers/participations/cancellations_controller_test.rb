require "test_helper"

module Participations
  class CancellationsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @event = events(:planning)
      @organizer = participants(:planning_organizer)
      @organizer_token = raw_token(:planning_organizer)
      @guest_token = raw_token(:planning_guest)
    end

    test "a guest token is not found in both families and the event stays open" do
      post participation_cancellation_path(@guest_token)
      assert_response :not_found
      assert_select "#link-not-found"

      sign_in users(:invitee)
      post my_participation_cancellation_path(participants(:planning_guest))
      assert_response :not_found

      assert_not @event.reload.cancelled?
      assert_equal 0, MailDelivery.cancelled.count
    end

    test "the organizer cancels through the token family and everyone linked is told once" do
      assert_difference "MailDelivery.cancelled.count", 3 do
        assert_enqueued_jobs 3, only: MailDeliveryJob do
          post participation_cancellation_path(@organizer_token)
        end
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Event cancelled. 3 people were told.", flash[:notice]
      @event.reload
      assert @event.cancelled?
      assert_equal 1, @event.revision
      assert_equal 1, @event.notified_revision
      assert_equal %w[invitee@example.com owner@example.com pending@example.com], MailDelivery.cancelled.pluck(:recipient_email).sort
      assert_nil participants(:planning_unsent).reload.token_digest
      assert_nil participants(:planning_left).reload.token_digest
    end

    test "the organizer cancels a finalized event through the session family and the window stays" do
      finalized = events(:finalized)
      sign_in users(:owner)

      assert_difference "MailDelivery.cancelled.count", 2 do
        post my_participation_cancellation_path(participants(:finalized_organizer))
      end

      assert_response :see_other
      assert_redirected_to my_participation_path(participants(:finalized_organizer))
      assert_equal "Event cancelled. 2 people were told.", flash[:notice]
      finalized.reload
      assert finalized.cancelled?
      assert finalized.status?
      assert_equal Time.utc(2030, 1, 15, 10), finalized.start_time
      assert_equal Time.utc(2030, 1, 15, 11), finalized.end_time
    end

    test "an organizer who never opened the link can cancel and is the one person told" do
      event = Event.plan!(
        attributes: { name: "Fresh", description: "new", slot_minutes: 60, time_zone: "UTC" },
        organizer: { email: "ann@example.com", name: "Ann", user: nil },
        starts_at: [ Time.utc(2031, 5, 1, 9) ],
        invitee_emails: [ "someone@example.com" ]
      )
      token = event.organizer.issue_live_token!

      post participation_cancellation_path(token)

      assert_redirected_to participation_path(token)
      assert_equal "Event cancelled. 1 person was told.", flash[:notice]
      assert_equal [ "ann@example.com" ], MailDelivery.cancelled.pluck(:recipient_email)
    end

    test "a second cancel is refused with one alert and no new ledger row" do
      @event.cancel!

      assert_no_difference "MailDelivery.count" do
        post participation_cancellation_path(@organizer_token)
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
    end

    test "after cancellation every write answers 303 with one alert and changes nothing" do
      @event.cancel!
      guest = participants(:planning_guest)
      item = activities(:planning_activity)
      snapshot = lambda do
        [ @event.reload.attributes, @event.participants.order(:id).map(&:attributes), @event.time_slots.order(:id).map(&:attributes),
          @event.activities.order(:id).map(&:attributes), MailDelivery.count ]
      end
      before = snapshot.call

      writes = {
        "invitations" => -> { post participation_invitations_path(@organizer_token), params: { invitations: { emails: "new@example.com" } } },
        "resend" => -> { post participation_participant_resend_path(@organizer_token, guest) },
        "link reveal" => -> { post participation_participant_link_reveal_path(@organizer_token, guest) },
        "remove" => -> { delete participation_participant_path(@organizer_token, guest) },
        "finalize" => -> { post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } } },
        "details" => -> { patch participation_details_path(@organizer_token), params: { event: { name: "Renamed" } } },
        "activity create" => -> { post participation_activities_path(@organizer_token), params: { activity: { name: "Late" } } },
        "activity update" => -> { patch participation_activity_path(@organizer_token, item), params: { activity: { name: "Late" } } },
        "activity destroy" => -> { delete participation_activity_path(@organizer_token, item) },
        "activity move" => -> { post participation_activity_move_path(@organizer_token, item), params: { move: { position: 0 } } },
        "cancel" => -> { post participation_cancellation_path(@organizer_token) }
      }
      writes.each do |name, write|
        write.call
        assert_response :see_other, name
        assert_redirected_to participation_path(@organizer_token), name
        assert_equal "This event was cancelled", flash[:alert], name
      end

      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
      assert_response :see_other
      assert_redirected_to participation_path(@guest_token)
      assert_equal "This event was cancelled", flash[:alert]
      post participation_decline_path(@guest_token)
      assert_response :see_other
      assert_equal "This event was cancelled", flash[:alert]

      assert_equal before, snapshot.call
    end

    test "the session family refuses writes on a cancelled event the same way" do
      @event.cancel!
      sign_in users(:owner)

      patch my_participation_details_path(@organizer), params: { event: { name: "Renamed" } }
      assert_response :see_other
      assert_redirected_to my_participation_path(@organizer)
      assert_equal "This event was cancelled", flash[:alert]

      post my_participation_invitations_path(@organizer)
      assert_redirected_to my_participation_path(@organizer)
      assert_equal "This event was cancelled", flash[:alert]

      post my_participation_cancellation_path(@organizer)
      assert_redirected_to my_participation_path(@organizer)
      assert_equal "This event was cancelled", flash[:alert]
      assert_equal "Planning session", @event.reload.name
    end

    test "a refused write promotes no pending token" do
      @event.cancel!
      guest = participants(:planning_guest)
      pending = guest.issue_pending_token!

      patch participation_path(pending), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }

      assert_equal "This event was cancelled", flash[:alert]
      guest.reload
      assert_equal Participant.digest(@guest_token), guest.token_digest
      assert_equal Participant.digest(pending), guest.pending_token_digest
      assert_equal users(:invitee).id, guest.user_id
    end

    test "Leave and Claim still work on a cancelled event" do
      @event.cancel!
      guest = participants(:planning_guest)

      delete participation_path(@guest_token)
      assert_response :see_other
      assert_redirected_to root_path
      assert_equal "You left Planning session.", flash[:notice]
      assert guest.reload.left_at.present?

      pending = participants(:planning_pending)
      sign_in users(:outsider)
      post participation_claim_path(raw_token(:planning_pending))
      assert_redirected_to my_participation_path(pending)
      assert_equal users(:outsider).id, pending.reload.user_id

      get dashboard_path
      assert_select "a[href=?] .event-face-state", my_participation_path(pending), text: /cancelled/
    end

    test "the cancelled organizer page is read-only with the plate, the zoned dates and Plan a new event" do
      finalized = events(:finalized)
      finalized.update_columns(time_zone: "Europe/Berlin")
      finalized.cancel!
      token = raw_token(:finalized_organizer)

      get participation_path(token)

      assert_response :success
      assert_select "table#time-grid-show[data-role=viewer][data-cancelled][data-finalized]"
      assert_select "h1", text: /Finalized event/ do
        assert_select "span.plate.plate-ink", text: "Cancelled"
        assert_select "span.plate", count: 1
      end
      assert_select ".event-when.is-cancelled" do
        assert_select "time.time[data-zoned-instant][datetime=?]", finalized.cancelled_at.utc.iso8601, text: %r{\(Europe/Berlin\)\z}
        assert_select "time.time[data-zoned-instant][datetime=?]", "2030-01-15T10:00:00Z", text: "Tue 15 Jan 2030 11:00 (Europe/Berlin)"
        assert_select "time.time[data-zoned-instant][datetime=?]", "2030-01-15T11:00:00Z", text: "12:00 (Europe/Berlin)"
      end
      assert_match "Cancelled on", response.body
      assert_match "Was set for", response.body
      assert_select "#final-window-local", count: 0
      assert_select "a.plate-button-sm[href=?]", new_event_path, text: "Plan a new event"
      assert_select "a[href=?]", edit_participation_details_path(token), count: 0
      assert_select "#participant-table tbody tr", count: 1
      assert_select "form", count: 0
      assert_select "button[type=submit], input[type=submit]", count: 0
    end

    test "a cancelled pending organizer page has no window line and no controls in either family" do
      @event.cancel!

      get participation_path(@organizer_token)

      assert_response :success
      assert_select "table#time-grid-show[data-role=viewer][data-cancelled]:not([data-finalized])"
      assert_select "h1 span.plate.plate-ink", text: "Cancelled"
      assert_select ".event-when.is-cancelled time[data-zoned-instant]", count: 1
      assert_match "Cancelled on", response.body
      assert_no_match "Was set for", response.body
      assert_no_match "Time to be confirmed", response.body
      assert_no_match "Send the link again", response.body
      assert_select "a", text: "Plan a new event"
      assert_select "a", text: "Edit details", count: 0
      assert_select "#participant-table tbody tr", count: 4
      assert_select "form", count: 0

      sign_in users(:owner)
      get my_participation_path(@organizer)
      assert_response :success
      assert_select "table#time-grid-show[data-role=viewer][data-cancelled]"
      assert_select "form", count: 0
      assert_select "a.plate-button-sm[href=?]", new_event_path, text: "Plan a new event"
    end

    test "the cancelled guest page keeps Leave and Claim and nothing else" do
      @event.cancel!

      get participation_path(@guest_token)

      assert_response :success
      assert_select "table#time-grid-show[data-role=viewer][data-cancelled]"
      assert_select "h1 span.plate.plate-ink", text: "Cancelled"
      assert_match "Cancelled on", response.body
      assert_select "#availability-form", count: 0
      assert_select "#finalize-form", count: 0
      assert_select "form[action=?]", participation_decline_path(@guest_token), count: 0
      assert_select "form[action=?] input[name=_method][value=delete]", participation_path(@guest_token)
      assert_select "button", text: "Leave this event"
      assert_select "button", text: "Save", count: 0
      assert_select "form", count: 1

      get participation_path(raw_token(:planning_pending))
      assert_select "a[href=?]", participation_claim_path(raw_token(:planning_pending)), text: "Keep this event in your account"
      assert_select "button", text: "Leave this event"

      sign_in users(:invitee)
      get my_participation_path(participants(:planning_guest))
      assert_response :success
      assert_select "table#time-grid-show[data-role=viewer][data-cancelled]"
      assert_select "form[action=?] input[name=_method][value=delete]", my_participation_path(participants(:planning_guest))
      assert_select "#availability-form", count: 0
    end

    test "Edit details answers the same alert on GET once cancelled" do
      @event.cancel!

      get edit_participation_details_path(@organizer_token)

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
    end
  end
end
