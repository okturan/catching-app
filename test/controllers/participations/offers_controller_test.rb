require "test_helper"

module Participations
  class OffersControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionMailer::TestCase::ClearTestDeliveries

    setup do
      @event = events(:planning)
      @organizer = participants(:planning_organizer)
      @guest = participants(:planning_guest)
      @organizer_token = raw_token(:planning_organizer)
      @guest_token = raw_token(:planning_guest)
      @ten = "2030-01-15T10:00:00Z"
      @eleven = "2030-01-15T11:00:00Z"
      @twelve = "2030-01-15T12:00:00Z"
      @thirteen = "2030-01-15T13:00:00Z"
    end

    def offer
      @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
    end

    # A fresh event the signed-in owner organizes, before any guest replied.
    def fresh_event(**attributes)
      event = Event.plan!(
        attributes: { name: "Fresh", description: "new", slot_minutes: 30, time_zone: "Europe/Berlin" }.merge(attributes),
        organizer: { email: users(:owner).email, name: users(:owner).full_name, user: users(:owner) },
        starts_at: [ Time.utc(2031, 5, 1, 9), Time.utc(2031, 5, 1, 9, 30) ],
        invitee_emails: [ "someone@example.com" ]
      )
      event.organizer.update_columns(link_opened_at: Time.current)
      [ event, event.organizer.issue_live_token! ]
    end

    test "a guest token is not found on edit and update in both families, and the offer is unchanged" do
      before = offer

      get edit_participation_offer_path(@guest_token)
      assert_response :not_found
      assert_select "#link-not-found"
      patch participation_offer_path(@guest_token), params: { time_slots: { time_slot_array: @twelve } }
      assert_response :not_found

      sign_in users(:invitee)
      get edit_my_participation_offer_path(@guest)
      assert_response :not_found
      patch my_participation_offer_path(@guest), params: { time_slots: { time_slot_array: @twelve } }
      assert_response :not_found

      assert_equal before, offer
    end

    test "the organizer page offers Change the times only while the event is open" do
      get participation_path(@organizer_token)
      assert_select ".event-panel a.plate-button-sm[href=?]", edit_participation_offer_path(@organizer_token), text: "Change the times"

      sign_in users(:owner)
      get my_participation_path(@organizer)
      assert_select "a.plate-button-sm[href=?]", edit_my_participation_offer_path(@organizer), text: "Change the times"

      get participation_path(raw_token(:finalized_organizer))
      assert_select "a", text: "Change the times", count: 0

      @event.update_columns(cancelled_at: Time.current)
      get participation_path(@organizer_token)
      assert_select "a", text: "Change the times", count: 0

      get participation_path(@guest_token)
      assert_select "a", text: "Change the times", count: 0
    end

    test "the offer page hydrates the definer with the future offer, the guests' picks and frozen step and zone" do
      get edit_participation_offer_path(@organizer_token)

      assert_response :success
      assert_select "h1", text: "Change the times"
      assert_select "form#offer-form[action=?][method=post]", participation_offer_path(@organizer_token) do
        assert_select "input[name='_method'][value=patch]"
        assert_select "input#time_slot_array[name='time_slots[time_slot_array]'][type=hidden][value=?]", "#{@ten},#{@eleven}"
        assert_select "input#current-offer[type=hidden][value=?]", [ @ten, @eleven ].to_json
        assert_select "input#guest-picked-counts[type=hidden][value=?]", { @ten => 1 }.to_json
        assert_select "select#event_slot_minutes[name='event[slot_minutes]'][disabled][aria-describedby=grid-frozen-note]" do
          assert_select "option[value='60'][selected]", "60 minutes"
        end
        assert_select "select#timezone-picker-new[name='event[time_zone]'][disabled][aria-describedby=grid-frozen-note][data-selected=UTC]"
        assert_select "#grid-frozen-note", text: "Fixed since the first reply"
        assert_select "input#event-begin[type=date][min=?]:not([name])", Time.current.utc.to_date.iso8601
        assert_select "input#event-end[type=date]:not([name])"
        assert_select "#range-tooltip[role=status]"
        assert_select "input#notice_send[type=checkbox][name='notice[send]'][value='1'][checked]"
        assert_select "label[for=notice_send]", text: "Email the guests who already replied"
        assert_select "input[type=submit][value='Save the new times']"
        assert_select "[name='event[duration_minutes]']", count: 0
        assert_select "[name='event[name]']", count: 0
      end
      assert_select ".offer-note", count: 0
      assert_select "table#time-grid-define[role=grid][data-slot-minutes='60'][data-time-zone='UTC'][data-not-before]"
      not_before = css_select("#time-grid-define").first["data-not-before"]
      assert_in_delta TimeSlotParser::PAST_GRACE.ago, Time.iso8601(not_before), 60
      assert_select "#selection-summary[aria-live=polite]"
      assert_select "#paint-mode[role=radiogroup]"
      assert_select "a[href=?]", participation_path(@organizer_token), text: "Back to the event"
      assert_select "form form", count: 0
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_select 'meta[name="robots"][content="noindex"]'
    end

    test "instants behind the cut-off stay out of the hydration and are counted in the caption; counts cover replied guests only" do
      past = 2.days.ago.utc.beginning_of_hour
      now = Time.current
      declined = @event.participants.create!(role: :guest, email: "declined@example.com", token_digest: "d" * 64,
        responded_at: 3.days.ago, declined_at: 3.days.ago)
      TimeSlot.insert_all!([
        { participant_id: @organizer.id, event_id: @event.id, start_time: past, created_at: now, updated_at: now },
        { participant_id: @guest.id, event_id: @event.id, start_time: past, created_at: now, updated_at: now },
        { participant_id: declined.id, event_id: @event.id, start_time: Time.utc(2030, 1, 15, 11), created_at: now, updated_at: now },
        { participant_id: participants(:planning_pending).id, event_id: @event.id, start_time: Time.utc(2030, 1, 15, 11), created_at: now, updated_at: now }
      ])

      get edit_participation_offer_path(@organizer_token)

      assert_response :success
      assert_select "input#time_slot_array[value=?]", "#{@ten},#{@eleven}"
      assert_select "input#current-offer[value=?]", [ @ten, @eleven ].to_json
      assert_select ".offer-note", text: "1 past time stays as it is"
      counts = JSON.parse(css_select("#guest-picked-counts").first["value"])
      assert_equal 1, counts[@ten]
      assert_nil counts[@eleven], "declined and unreplied guests hold nothing that counts"
      assert_equal 1, counts[past.iso8601], "a past pick still shows on its cell"
    end

    test "before the first reply step and zone are live, accepted and echoed through the session family" do
      event, token = fresh_event
      organizer = event.organizer

      get edit_participation_offer_path(token)
      assert_response :success
      assert_select "select#event_slot_minutes:not([disabled])[aria-describedby=slot-minutes-hint]"
      assert_select "select#timezone-picker-new:not([disabled])[data-selected='Europe/Berlin']"
      assert_select "#grid-frozen-note", count: 0
      assert_select "input#event-begin[min=?]", Time.current.in_time_zone("Europe/Berlin").to_date.iso8601

      sign_in users(:owner)
      get edit_my_participation_offer_path(organizer)
      assert_response :success
      assert_select "form#offer-form[action=?]", my_participation_offer_path(organizer)

      assert_no_difference "MailDelivery.count" do
        patch my_participation_offer_path(organizer), params: {
          event: { slot_minutes: "60", time_zone: "Asia/Kolkata" },
          time_slots: { time_slot_array: "2031-05-01T04:30:00Z,2031-05-01T05:30:00Z" },
          notice: { send: "1" }
        }
      end
      assert_response :see_other
      assert_redirected_to my_participation_path(organizer)
      assert_equal "Times updated: 2 added, 2 removed.", flash[:notice], "no guest replied, so nobody is emailed"
      event.reload
      assert_equal [ 60, "Asia/Kolkata", 1 ], [ event.slot_minutes, event.time_zone, event.revision ]
      assert_equal [ Time.utc(2031, 5, 1, 4, 30), Time.utc(2031, 5, 1, 5, 30) ], event.time_slots.order(:start_time).pluck(:start_time)
      assert_equal 2, event.offer_revision_added
    end

    test "a zone change alone updates the grid and says so; the same offer again changes nothing" do
      event, token = fresh_event
      slots = event.time_slots.order(:id).map(&:attributes)

      patch participation_offer_path(token), params: {
        event: { time_zone: "Europe/Paris" }, time_slots: { time_slot_array: "2031-05-01T09:00:00Z,2031-05-01T09:30:00Z" }, notice: { send: "1" }
      }
      assert_response :see_other
      assert_equal "Slot length and zone updated.", flash[:notice]
      event.reload
      assert_equal [ "Europe/Paris", 1 ], [ event.time_zone, event.revision ]
      assert_nil event.offer_revised_at
      assert_equal slots, event.time_slots.order(:id).map(&:attributes)

      assert_no_difference "MailDelivery.count" do
        patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@eleven},#{@ten}" }, notice: { send: "1" } }
      end
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Nothing changed.", flash[:notice]
      @event.reload
      assert_equal 0, @event.revision
      assert_nil @event.offer_revised_at
    end

    test "a removal deletes the guests' picks, voids a guest left with nothing and emails the guests who replied" do
      pending = participants(:planning_pending)
      pending.update_columns(responded_at: 2.days.ago)
      @event.replace_time_slots!(participant: pending, starts_at: [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ])
      @event.update_columns(revision: 1, notified_revision: 1)

      assert_difference "MailDelivery.event_updated.count", 2 do
        perform_enqueued_jobs do
          patch participation_offer_path(@organizer_token), params: {
            event: { slot_minutes: "30", time_zone: "Asia/Kolkata" },
            time_slots: { time_slot_array: "#{@eleven},#{@twelve},#{@thirteen}" }, notice: { send: "1" }
          }
        end
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Times updated: 2 added, 1 removed. 2 guests emailed. 1 guest needs a new reply.", flash[:notice]
      @event.reload
      assert_equal [ 60, "UTC" ], [ @event.slot_minutes, @event.time_zone ], "step and zone are ignored after the first reply"
      assert_equal [ 11, 12, 13 ].map { |h| Time.utc(2030, 1, 15, h) }, offer
      assert_equal [ 2, 1, 2, 2 ], [ @event.offer_revision_added, @event.offer_revision_removed, @event.revision, @event.notified_revision ]
      @guest.reload
      assert @guest.reply_voided_at.present?
      assert_equal 0, @guest.time_slots.count
      assert_equal Time.utc(2030, 1, 2, 9), @guest.responded_at, "the reply stays on record"
      assert_equal [ Time.utc(2030, 1, 15, 11) ], pending.time_slots.pluck(:start_time), "the trimmed guest keeps 11:00"
      assert_nil pending.reload.reply_voided_at

      mails = ActionMailer::Base.deliveries.last(2).index_by { |mail| mail.to.first }
      assert_equal %w[invitee@example.com pending@example.com], mails.keys.sort
      voided_body = mails["invitee@example.com"].text_part.body.to_s
      assert_includes voided_body, "Olivia Owner changed the offered times for Planning session."
      assert_includes voided_body, "None of the times you picked are offered any more. Please pick again."
      assert_includes voided_body, "/participations/#{@guest.id}"
      trimmed_body = mails["pending@example.com"].text_part.body.to_s
      assert_includes trimmed_body, "Some of the offered times changed (2 added, 1 removed). Your remaining picks still stand; look again."
      assert_match %r{http://example.com/p/[A-Za-z0-9]{32}}, trimmed_body

      get participation_path(@organizer_token)
      assert_select "#participant-table td", text: "needs a new reply"
      assert_select "#participant-table td", text: "replied (1 slot, before the last change)"
    end

    test "an unticked box, an unreplied guest and a removal-only revision for a declined guest send nothing" do
      pending = participants(:planning_pending)
      declined = @event.participants.create!(role: :guest, email: "declined@example.com", token_digest: "d" * 64,
        responded_at: 3.days.ago, declined_at: 3.days.ago)

      assert_no_difference "MailDelivery.count" do
        patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@ten},#{@eleven},#{@twelve}" }, notice: { send: "0" } }
      end
      assert_equal "Times updated: 1 added, 0 removed.", flash[:notice]

      assert_difference "MailDelivery.event_updated.count", 1 do
        patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@ten},#{@eleven}" }, notice: { send: "1" } }
      end
      assert_equal "Times updated: 0 added, 1 removed. 1 guest emailed.", flash[:notice]
      assert_equal [ @guest.email ], MailDelivery.event_updated.pluck(:recipient_email), "removal only: the declined and the unreplied guest hear nothing"
      assert_nil pending.reload.pending_token_digest

      MailDelivery.event_updated.update_all(created_at: 11.minutes.ago)
      assert_difference "MailDelivery.event_updated.count", 2 do
        patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@ten},#{@eleven},#{@twelve}" }, notice: { send: "1" } }
      end
      assert_equal %w[declined@example.com invitee@example.com], MailDelivery.event_updated.where(created_at: 1.minute.ago..).pluck(:recipient_email).sort,
        "an addition reaches the declined guest"
      assert_nil declined.reload.reply_voided_at
    end

    test "a capped recipient is skipped and counted, never raised" do
      5.times do |i|
        MailDelivery.create!(event: @event, participant: @guest, kind: :event_updated, recipient_email: @guest.email,
          sender_email: "owner@example.com", created_at: (i + 1).hours.ago)
      end

      assert_no_difference "MailDelivery.count" do
        patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@ten},#{@eleven},#{@twelve}" }, notice: { send: "1" } }
      end

      assert_response :see_other
      assert_equal "Times updated: 1 added, 0 removed. 0 guests emailed. 1 skipped (recently notified). Try again after 10 minutes.", flash[:notice]
      assert_equal 3, offer.size
      assert_equal 0, @event.reload.notified_revision
    end

    test "a ticked box from an organizer who never opened the link saves the times and answers the hint" do
      @organizer.update_columns(link_opened_at: nil)

      get edit_participation_offer_path(@organizer_token)
      assert_response :success
      assert_select "[name='notice[send]']", count: 0

      assert_no_difference "MailDelivery.count" do
        patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@ten},#{@eleven},#{@twelve}" }, notice: { send: "1" } }
      end
      assert_response :see_other
      assert_equal "Times updated: 1 added, 0 removed.", flash[:notice]
      assert_equal "Open your organizer link before emailing guests", flash[:alert]
      assert_equal 3, offer.size
    end

    test "a step change that no longer fits the planned length clears it and says so" do
      event, token = fresh_event(duration_minutes: 90)

      patch participation_offer_path(token), params: {
        event: { slot_minutes: "60" }, time_slots: { time_slot_array: "2031-05-01T09:00:00Z" }
      }

      assert_response :see_other
      assert flash[:notice].end_with?("Planned length cleared: it no longer fits 60-minute slots."), flash[:notice]
      assert flash[:notice].start_with?("Times updated: 0 added, 1 removed."), flash[:notice]
      event.reload
      assert_nil event.duration_minutes
      assert_equal 60, event.slot_minutes
    end

    test "parser, grid and step failures re-render the page with 422 and the paint echoed" do
      before = offer

      yesterday = 2.days.ago.utc.beginning_of_hour.iso8601
      patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: yesterday } }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: "Select time slots from today onward"
      assert_select "input#time_slot_array[value=?]", yesterday
      assert_select "form#offer-form"
      assert_select "table#time-grid-define[data-not-before]"

      patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "#{@ten},2030-01-15T10:30:00Z" } }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: "Select time slots on the event's 60-minute grid"
      assert_select "input#time_slot_array[value=?]", "#{@ten},2030-01-15T10:30:00Z"

      patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "" } }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: "Select at least one time slot"

      patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: "nonsense" } }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: "Time slots must use ISO 8601 timestamps"

      event, token = fresh_event
      patch participation_offer_path(token), params: { event: { time_zone: "Mars/Olympus" }, time_slots: { time_slot_array: "2031-05-01T09:00:00Z" } }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", text: /is not a known time zone/
      assert_equal "Europe/Berlin", event.reload.time_zone

      assert_equal before, offer
      assert_equal 0, @event.reload.revision
    end

    test "a finalized event asks for a reopen first and a cancelled one answers the cancelled alert, in both families" do
      finalized = events(:finalized)
      token = raw_token(:finalized_organizer)
      before = finalized.time_slots.order(:id).pluck(:id)

      get edit_participation_offer_path(token)
      assert_response :see_other
      assert_redirected_to participation_path(token)
      assert_equal "Reopen the time before changing the offer", flash[:alert]

      patch participation_offer_path(token), params: { time_slots: { time_slot_array: @twelve } }
      assert_response :see_other
      assert_redirected_to participation_path(token)
      assert_equal "Reopen the time before changing the offer", flash[:alert]

      sign_in users(:owner)
      get edit_my_participation_offer_path(participants(:finalized_organizer))
      assert_response :see_other
      assert_equal "Reopen the time before changing the offer", flash[:alert]
      assert_equal before, finalized.time_slots.order(:id).pluck(:id)

      @event.update_columns(cancelled_at: Time.current)
      get edit_participation_offer_path(@organizer_token)
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]

      patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: @twelve } }
      assert_response :see_other
      assert_equal "This event was cancelled", flash[:alert]

      patch my_participation_offer_path(@organizer), params: { time_slots: { time_slot_array: @twelve } }
      assert_response :see_other
      assert_equal "This event was cancelled", flash[:alert]
      assert_equal [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ], offer
    end

    test "the session family needs a session and hides other accounts" do
      get edit_my_participation_offer_path(@organizer)
      assert_redirected_to new_user_session_path

      sign_in users(:outsider)
      get edit_my_participation_offer_path(@organizer)
      assert_response :not_found
    end
  end
end
