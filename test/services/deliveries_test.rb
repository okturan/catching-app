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

  test "finalized! links unclaimed guests through a fresh pending token, claimed ones by account, the organizer not at all" do
    @event.update_columns(status: true, start_time: Time.utc(2030, 1, 15, 10), end_time: Time.utc(2030, 1, 15, 11), revision: 2)
    pending = participants(:planning_pending)
    stale = pending.issue_pending_token!
    live_guest_digest = @guest.token_digest

    assert_difference "MailDelivery.finalized.count", 3 do
      assert_enqueued_jobs 3, only: MailDeliveryJob do
        Deliveries.finalized!(event: @event)
      end
    end

    pending.reload
    assert pending.pending_token_digest.present?
    assert_not_equal Participant.digest(stale), pending.pending_token_digest, "the previous pending token retires"
    assert_nil pending.pending_token_expires_at
    assert_equal Participant.digest(raw_token(:planning_pending)), pending.token_digest, "the live token keeps working"
    assert_nil @guest.reload.pending_token_digest, "a claimed guest gets no token"
    assert_equal live_guest_digest, @guest.token_digest
    assert_nil @organizer.reload.pending_token_digest
    assert_equal 2, @event.reload.notified_revision
    assert_equal %w[invitee@example.com owner@example.com pending@example.com], MailDelivery.finalized.pluck(:recipient_email).sort

    perform_enqueued_jobs
    mails = ActionMailer::Base.deliveries.last(3).index_by { |mail| mail.to.first }
    pending_body = mails["pending@example.com"].text_part.body.to_s
    assert_match %r{http://example.com/p/[A-Za-z0-9]{32}}, pending_body
    assert_not_includes pending_body, raw_token(:planning_pending), "never the live token"
    assert_includes mails["invitee@example.com"].text_part.body.to_s, "http://example.com/participations/#{@guest.id}"
    assert_not_includes mails["invitee@example.com"].text_part.body.to_s, "/p/"
    organizer_body = mails["owner@example.com"].text_part.body.to_s
    assert_not_includes organizer_body, "://"
    assert_includes organizer_body, "Open your organizer link"
    mails.each_value { |mail| assert_equal [ "catching-app.ics" ], mail.attachments.map(&:filename) }
  end

  test "finalized! prints the window from the job's own params after a reopen-shaped change" do
    finalized = events(:finalized)

    assert_enqueued_jobs 2, only: MailDeliveryJob do
      Deliveries.finalized!(event: finalized)
    end
    finalized.update_columns(status: false, start_time: nil, end_time: nil)

    assert_nothing_raised { perform_enqueued_jobs }
    mails = ActionMailer::Base.deliveries.last(2)
    mails.each do |mail|
      assert_includes mail.text_part.body.to_s, "Tue 15 Jan 2030 10:00–11:00 (UTC)"
      assert_includes mail.attachments.first.body.decoded, "DTSTART:20300115T100000Z"
    end
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
