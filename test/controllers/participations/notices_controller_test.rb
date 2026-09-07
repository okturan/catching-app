require "test_helper"

module Participations
  class NoticesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionMailer::TestCase::ClearTestDeliveries

    setup do
      @event = events(:planning)
      @organizer = participants(:planning_organizer)
      @organizer_token = raw_token(:planning_organizer)
      @event.update_columns(revision: 2, notified_revision: 1)
    end

    test "a guest token is not found in either family and nothing is sent" do
      assert_no_difference "MailDelivery.count" do
        post participation_notice_path(raw_token(:planning_guest))
      end
      assert_response :not_found
      assert_select "#link-not-found"

      sign_in users(:invitee)
      post my_participation_notice_path(participants(:planning_guest))
      assert_response :not_found
      assert_equal 1, @event.reload.notified_revision
    end

    test "an organizer who has not opened the link is sent back with the hint and nothing is sent" do
      @organizer.update_columns(link_opened_at: nil)

      assert_no_difference "MailDelivery.count" do
        post participation_notice_path(@organizer_token)
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Open your organizer link before emailing guests", flash[:alert]
      assert_equal 1, @event.reload.notified_revision
    end

    test "nothing to tell answers without sending" do
      @event.update_columns(notified_revision: 2)

      assert_no_difference "MailDelivery.count" do
        post participation_notice_path(@organizer_token)
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Guests already know about every change.", flash[:alert]
    end

    test "the organizer tells every linked guest through either family; the previous pending link stops working, the live one keeps opening" do
      pending = participants(:planning_pending)
      stale = pending.issue_pending_token!

      assert_difference "MailDelivery.event_updated.count", 2 do
        perform_enqueued_jobs do
          post participation_notice_path(@organizer_token)
        end
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "2 guests emailed.", flash[:notice]
      assert_equal 2, @event.reload.notified_revision
      rows = MailDelivery.event_updated.order(:id)
      assert_equal %w[invitee@example.com pending@example.com], rows.map(&:recipient_email).sort
      assert rows.all? { |row| row.sender_email == "owner@example.com" && row.request_ip.present? && row.delivered_at.present? }

      mails = ActionMailer::Base.deliveries.last(2).index_by { |mail| mail.to.first }
      fresh = mails["pending@example.com"].text_part.body.to_s[%r{/p/([A-Za-z0-9]{32})}, 1]
      assert fresh
      assert_not_equal stale, fresh
      digests = -> { pending.reload.values_at(:token_digest, :pending_token_digest) }
      before = digests.call
      get participation_path(fresh)
      assert_response :success
      assert_equal before, digests.call, "a GET with the pending token changes no digest"

      get participation_path(stale)
      assert_response :not_found
      assert_select "#link-not-found h1", text: "This link is not valid."
      assert_select "#link-not-found p", text: "Open the newest email about this event: a newer link replaces older ones, or ask the organizer to resend your invitation."
      get participation_path(raw_token(:planning_pending))
      assert_response :success

      claimed_body = mails["invitee@example.com"].text_part.body.to_s
      assert_includes claimed_body, "/participations/#{participants(:planning_guest).id}"
      assert_not_includes claimed_body, "/p/"
      assert_includes claimed_body, "Olivia Owner changed Planning session. Here is what is set now."
      assert_nil participants(:planning_guest).reload.pending_token_digest

      @event.update_columns(revision: 3)
      MailDelivery.event_updated.update_all(created_at: 11.minutes.ago)
      sign_in users(:owner)
      assert_difference "MailDelivery.event_updated.count", 2 do
        post my_participation_notice_path(@organizer)
      end
      assert_redirected_to my_participation_path(@organizer)
      assert_equal "2 guests emailed.", flash[:notice]
      assert_equal 3, @event.reload.notified_revision
    end

    test "guests inside the cooldown are skipped and the organizer hears how long to wait" do
      MailDelivery.create!(event: @event, participant: participants(:planning_guest), kind: :event_updated,
        recipient_email: "invitee@example.com", sender_email: "owner@example.com", created_at: 5.minutes.ago)

      assert_difference "MailDelivery.event_updated.count", 1 do
        post participation_notice_path(@organizer_token)
      end

      assert_equal "1 guest emailed. 1 skipped (recently notified). Try again after 10 minutes.", flash[:notice]
      assert_equal "pending@example.com", MailDelivery.event_updated.order(:id).last.recipient_email
      assert_equal 2, @event.reload.notified_revision
    end

    test "a cancelled event refuses the notice with one alert" do
      @event.cancel!

      assert_no_difference "MailDelivery.event_updated.count" do
        post participation_notice_path(@organizer_token)
      end

      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
    end
  end
end
