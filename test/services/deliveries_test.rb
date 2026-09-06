require "test_helper"

class DeliveriesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestCase::ClearTestDeliveries

  setup do
    @event = events(:planning)
    @organizer = participants(:planning_organizer)
    @guest = participants(:planning_guest)
  end

  test "every kind but cancelled raises on a cancelled event and writes nothing" do
    @event.cancel!
    unsent = participants(:planning_unsent)
    calls = {
      "invitation!" => -> { Deliveries.invitation!(event: @event, guest: unsent, organizer: @organizer, request_ip: "203.0.113.1") },
      "organizer_link!" => -> { Deliveries.organizer_link!(event: @event, organizer: @organizer, request_ip: nil, pending: true) },
      "response_confirmation!" => -> { Deliveries.response_confirmation!(event: @event, guest: @guest) },
      "finalized!" => -> { Deliveries.finalized!(event: @event) },
      "reveal_link!" => -> { Deliveries.reveal_link!(event: @event, guest: @guest, organizer: @organizer, request_ip: nil) }
    }

    assert_no_difference "MailDelivery.count" do
      assert_no_enqueued_jobs do
        calls.each do |name, call|
          error = assert_raises(Event::ClosedError, name) { call.call }
          assert_equal "This event was cancelled", error.message, name
        end
      end
    end
    assert_nil unsent.reload.token_digest
    assert_nil @organizer.reload.pending_token_digest
    assert_nil @guest.reload.pending_token_digest
  end

  test "cancelled! tells every active linked participant once, the organizer included, and issues no token" do
    @event.update_columns(revision: 2)
    @guest.update!(declined_at: Time.current)
    @event.cancel!
    credentials = -> { @event.participants.order(:id).pluck(:token_digest, :pending_token_digest, :user_id) }
    before = credentials.call

    told = nil
    assert_difference "MailDelivery.cancelled.count", 3 do
      assert_enqueued_jobs 3, only: MailDeliveryJob do
        told = Deliveries.cancelled!(event: @event)
      end
    end

    assert_equal 3, told
    rows = MailDelivery.cancelled.order(:id)
    assert_equal %w[invitee@example.com owner@example.com pending@example.com], rows.map(&:recipient_email).sort
    assert rows.all? { |row| row.sender_email == "owner@example.com" }, "the organizer's canonical address is the sender"
    assert rows.all? { |row| row.participant_id.present? && row.request_ip.nil? }
    assert_equal before, credentials.call
    assert_equal 3, @event.reload.notified_revision
  end

  test "cancelled! is never capped and reaches a recipient every other kind would skip" do
    10.times do |i|
      MailDelivery.create!(event: events(:other_event), kind: :invitation, recipient_email: @guest.email,
        sender_email: "o#{i}@example.com")
    end
    @event.cancel!

    assert_difference "MailDelivery.cancelled.where(recipient_email: 'invitee@example.com').count", 1 do
      Deliveries.cancelled!(event: @event)
    end
  end

  test "cancelled! prints the window from the job's own params and nothing for a pending event" do
    finalized = events(:finalized)
    finalized.cancel!

    perform_enqueued_jobs { Deliveries.cancelled!(event: finalized) }

    mails = ActionMailer::Base.deliveries.last(2)
    assert_equal [ "invitee@example.com", "owner@example.com" ], mails.flat_map(&:to).sort
    mails.each do |mail|
      assert_equal "Catching App: Finalized event is cancelled", mail.subject
      assert_includes mail.text_part.body.to_s, "It was set for Tue 15 Jan 2030 10:00–11:00 (UTC)."
      assert_not_includes mail.text_part.body.to_s, "://"
    end
    assert MailDelivery.cancelled.where(event: finalized).all? { |row| row.delivered_at.present? }

    @event.cancel!
    perform_enqueued_jobs { Deliveries.cancelled!(event: @event) }
    assert_not_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "It was set for"
  end
end
