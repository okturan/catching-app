require "test_helper"

module Participations
  class FinalizationsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionMailer::TestCase::ClearTestDeliveries

    setup do
      @event = events(:planning)
      @organizer_token = raw_token(:planning_organizer)
      @consensus = "2030-01-15T10:00:00Z"
    end

    test "organizer finalizes a mutually available slot and everyone linked is notified" do
      assert_difference "MailDelivery.finalized.count", 3 do
        post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: @consensus } }
      end

      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Meeting time confirmed.", flash[:notice]
      @event.reload
      assert @event.status?
      assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
      assert_equal Time.utc(2030, 1, 15, 11), @event.end_time
    end

    test "finalizing bumps the revision, marks guests told and hands unclaimed guests a fresh pending link" do
      pending = participants(:planning_pending)
      stale = pending.issue_pending_token!
      @event.update_columns(revision: 2, notified_revision: 1)

      perform_enqueued_jobs do
        post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: @consensus } }
      end

      @event.reload
      assert_equal 3, @event.revision
      assert_equal 3, @event.notified_revision
      mails = ActionMailer::Base.deliveries.last(3).index_by { |mail| mail.to.first }
      assert_equal %w[invitee@example.com owner@example.com pending@example.com], mails.keys.sort
      assert mails.values.all? { |mail| mail.attachments.map(&:filename) == [ "catching-app.ics" ] }

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
      get participation_path(raw_token(:planning_pending))
      assert_response :success

      assert_includes mails["invitee@example.com"].text_part.body.to_s, "/participations/#{participants(:planning_guest).id}"
      assert_nil participants(:planning_guest).reload.pending_token_digest
      assert_not_includes mails["owner@example.com"].text_part.body.to_s, "://"
    end

    test "a shorter window than the planned length still finalizes" do
      @event.update!(duration_minutes: 120)

      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: @consensus } }

      assert_response :see_other
      assert_equal "Meeting time confirmed.", flash[:notice]
      assert @event.reload.status?
    end

    test "a guest token cannot finalize" do
      post participation_finalization_path(raw_token(:planning_guest)), params: { time_slots: { time_slot_array: @consensus } }

      assert_response :not_found
      assert_not @event.reload.status?
    end

    test "finalization errors redirect with the exact message" do
      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
      assert_response :see_other
      assert_equal "Select only time slots available to every participant", flash[:alert]

      later = Time.utc(2030, 1, 15, 12)
      @event.replace_time_slots!(participant: participants(:planning_organizer), starts_at: [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11), later ])
      @event.replace_time_slots!(participant: participants(:planning_guest), starts_at: [ Time.utc(2030, 1, 15, 10), later ])
      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: [ @consensus, later.iso8601 ].join(",") } }
      assert_response :see_other
      assert_equal "Select one continuous meeting window", flash[:alert]

      post participation_finalization_path(raw_token(:finalized_organizer)), params: { time_slots: { time_slot_array: @consensus } }
      assert_response :see_other
      assert_equal "Availability is closed for this event", flash[:alert]
    end

    test "an event nobody replied to cannot be finalized" do
      participants(:planning_guest).update!(declined_at: Time.current)

      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: @consensus } }

      assert_response :see_other
      assert_equal "Wait for at least one reply before confirming", flash[:alert]
    end
  end
end
