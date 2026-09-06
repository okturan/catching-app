require "test_helper"

module Participations
  class ReopeningsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionMailer::TestCase::ClearTestDeliveries

    setup do
      @event = events(:finalized)
      @organizer = participants(:finalized_organizer)
      @guest = participants(:finalized_guest)
      @organizer_token = raw_token(:finalized_organizer)
      @guest_token = raw_token(:finalized_guest)
    end

    def add_linked_guest(email)
      guest = @event.participants.create!(role: :guest, email: email)
      [ guest, guest.issue_live_token! ]
    end

    test "a guest token is not found in both families and the window stays" do
      post participation_reopening_path(@guest_token)
      assert_response :not_found
      assert_select "#link-not-found"

      sign_in users(:invitee)
      post my_participation_reopening_path(@guest)
      assert_response :not_found

      @event.reload
      assert @event.status?
      assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
      assert_equal 0, @event.reopen_count
      assert_equal 0, MailDelivery.reopened.count
    end

    test "the finalized organizer page offers Reopen the time with the confirm next to Cancel, and no guest page does" do
      get participation_path(@organizer_token)

      assert_response :success
      assert_select ".event-organizer-ends" do
        assert_select "form[action=?][method=post]", participation_reopening_path(@organizer_token) do
          assert_select "button.btn.btn-outline-secondary", text: "Reopen the time"
        end
        assert_select "form[action=?]", participation_cancellation_path(@organizer_token)
      end
      form = css_select("form[action='#{participation_reopening_path(@organizer_token)}']").first
      assert_equal "Withdraw Tue 15 Jan 10:00–11:00 (UTC)? Everyone with a link is told once and can paint again.", form["data-turbo-confirm"]
      assert_select ".event-reopened", count: 0

      @event.update_columns(reopen_count: 2, reopened_at: Time.utc(2030, 1, 12, 9))
      get participation_path(@organizer_token)
      assert_select ".event-reopened span", text: "Reopened twice — the last time"
      assert_select "form[action=?]", participation_reopening_path(@organizer_token)

      get participation_path(@guest_token)
      assert_select "form[action=?]", participation_reopening_path(@guest_token), count: 0
      assert_select "button", text: "Reopen the time", count: 0
      assert_select ".event-reopened", count: 0

      get participation_path(raw_token(:planning_organizer))
      assert_select "button", { text: "Reopen the time", count: 0 }, "a pending event has nothing to reopen"
    end

    test "the organizer reopens through the token family: the guests are told once, the page plans again and the file is gone" do
      second, second_token = add_linked_guest("second@example.com")
      @event.participants.create!(role: :guest, email: "unsent@example.com")
      @event.update_columns(revision: 4, notified_revision: 4)

      assert_difference "MailDelivery.reopened.count", 2 do
        assert_enqueued_jobs 2, only: MailDeliveryJob do
          post participation_reopening_path(@organizer_token)
        end
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "The set time was withdrawn. 2 guests were told.", flash[:notice]
      @event.reload
      assert_not @event.status?
      assert @event.open?
      assert_nil @event.start_time
      assert_nil @event.end_time
      assert_equal 1, @event.reopen_count
      assert_in_delta Time.current, @event.reopened_at, 5.seconds
      assert_equal 5, @event.revision
      assert_equal 5, @event.notified_revision
      assert_equal %w[invitee@example.com second@example.com], MailDelivery.reopened.pluck(:recipient_email).sort
      assert_equal 0, MailDelivery.reopened.where(participant: @organizer).count
      assert_equal @guest.time_slots.count, @event.time_slots.where(participant: @guest).count
      assert @guest.reload.responded_at.present?

      get participation_path(@organizer_token)
      assert_response :success
      assert_select "table#time-grid-show[data-role=organizer]:not([data-finalized])"
      assert_select "#consensus-time-slots[value=?]", [ "2030-01-15T10:00:00Z" ].to_json
      assert_select "#finalize-form"
      assert_select "button[form=finalize-form]", text: "Set in stone"
      assert_select "a.plate-button-sm[href=?]", edit_participation_offer_path(@organizer_token), text: "Change the times"
      assert_select "h1 .plate", count: 0
      assert_select ".event-when.is-pending", text: /Time to be confirmed/
      assert_select ".event-reopened" do
        assert_select "span", text: "Reopened once"
        assert_select "time.time[data-zoned-instant][datetime=?]", @event.reopened_at.utc.iso8601, text: /\(UTC\)\z/
      end
      assert_select "a", text: "Add to calendar", count: 0
      assert_select "button", text: "Reopen the time", count: 0
      assert_select "form[action=?]", participation_cancellation_path(@organizer_token)
      assert_select "#final-window", count: 0

      get participation_calendar_path(@organizer_token)
      assert_response :not_found

      get participation_path(second_token)
      assert_select "#availability-form"
      assert_select ".grid-notice", { count: 0 }, "a guest who never replied sees no note"
      assert_equal second, Participant.find_by_token(second_token)
    end

    test "the organizer reopens through the session family and the guest who replied reads the note" do
      @guest.update_columns(responded_at: 2.days.ago)
      sign_in users(:owner)

      post my_participation_reopening_path(@organizer)

      assert_response :see_other
      assert_redirected_to my_participation_path(@organizer)
      assert_equal "The set time was withdrawn. 1 guest was told.", flash[:notice]
      assert_not @event.reload.status?

      sign_in users(:invitee)
      get my_participation_path(@guest)
      assert_response :success
      assert_select "table#time-grid-show[data-role=guest]"
      assert_select "#availability-form"
      assert_select "#my-time-slots[value=?]", [ "2030-01-15T10:00:00Z" ].to_json
      assert_select ".grid-action-bar .grid-notice[role=status]", text: /\AThe set time was withdrawn on .* Check your picks and save\.\z/m do
        assert_select "time.time[data-zoned-instant][datetime=?]", @event.reopened_at.utc.iso8601
      end
    end

    test "a pending event and a third attempt are refused with the exact sentences and nothing is sent" do
      assert_no_difference "MailDelivery.count" do
        post participation_reopening_path(raw_token(:planning_organizer))
      end
      assert_response :see_other
      assert_redirected_to participation_path(raw_token(:planning_organizer))
      assert_equal "Only a set time can be reopened", flash[:alert]

      @event.update_columns(reopen_count: 2, revision: 9)
      assert_no_difference "MailDelivery.count" do
        post participation_reopening_path(@organizer_token)
      end
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was reopened twice already. Cancel it and plan a new one.", flash[:alert]
      @event.reload
      assert @event.status?
      assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
      assert_equal 2, @event.reopen_count
      assert_equal 9, @event.revision
    end

    test "when every offered time has passed the flash says so and both pages point at the times" do
      @event.time_slots.update_all(start_time: 3.days.ago.beginning_of_hour)

      post participation_reopening_path(@organizer_token)

      assert_response :see_other
      assert_equal "The set time was withdrawn. 1 guest was told. Every offered time has passed. Change the times.", flash[:notice]

      get participation_path(@organizer_token)
      assert_select ".grid-every-past" do
        assert_select "span", text: "Every offered time has passed."
        assert_select "a.plate-button-sm[href=?]", edit_participation_offer_path(@organizer_token), text: "Change the times"
      end
      assert_select "button[form=finalize-form]", count: 0

      get participation_path(@guest_token)
      assert_select "#selection-summary", text: "All the offered times have passed."
      assert_select "button[form=availability-form][hidden]", text: "Save"
    end

    test "the unclaimed guest is linked through a fresh pending token, the previous pending link dies and the claimed guest keeps the account link" do
      @guest.update!(user: nil, responded_at: 2.days.ago)
      stale = @guest.issue_pending_token!
      claimed, claimed_token = add_linked_guest("claimed@example.com")
      claimed.update!(user: users(:outsider))

      perform_enqueued_jobs do
        post participation_reopening_path(@organizer_token)
      end

      assert_equal "The set time was withdrawn. 2 guests were told.", flash[:notice]
      mails = ActionMailer::Base.deliveries.last(2).index_by { |mail| mail.to.first }
      assert_equal %w[claimed@example.com invitee@example.com], mails.keys.sort
      mails.each_value do |mail|
        assert_equal "Catching App: Finalized event is no longer set for Tue 15 Jan", mail.subject
        assert_includes mail.attachments.first.body.decoded, "STATUS:CANCELLED"
        assert_includes mail.attachments.first.body.decoded, "SEQUENCE:#{@event.reload.revision}"
      end

      fresh = mails["invitee@example.com"].text_part.body.to_s[%r{/p/([A-Za-z0-9]{32})}, 1]
      assert fresh
      assert_not_equal stale, fresh
      digests = -> { @guest.reload.values_at(:token_digest, :pending_token_digest) }
      before = digests.call
      get participation_path(fresh)
      assert_response :success
      assert_select ".grid-notice", text: /The set time was withdrawn on/
      assert_equal before, digests.call, "a GET with the pending token changes no digest"
      get participation_path(stale)
      assert_response :not_found
      get participation_path(@guest_token)
      assert_response :success

      claimed_body = mails["claimed@example.com"].text_part.body.to_s
      assert_includes claimed_body, "http://example.com/participations/#{claimed.id}"
      assert_not_includes claimed_body, "/p/"
      assert_nil claimed.reload.pending_token_digest
      assert_equal Participant.digest(claimed_token), claimed.token_digest
      assert MailDelivery.reopened.all? { |row| row.reload.delivered_at.present? && row.sender_email == "owner@example.com" }
    end
  end
end
