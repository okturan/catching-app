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
      "event_updated!" => -> { Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :all) },
      "reveal_link!" => -> { Deliveries.reveal_link!(event: @event, guest: @guest, organizer: @organizer, request_ip: nil) },
      "reopened!" => -> { Deliveries.reopened!(event: @event, previous_window: [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ]) }
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

  test "the first invitation marks the guests told about every revision so far; later invitees and resends tell nobody else" do
    @event.update_columns(revision: 3, notified_revision: 1)
    unsent = participants(:planning_unsent)

    Deliveries.invitation!(event: @event, guest: unsent, organizer: @organizer, request_ip: "203.0.113.1")
    assert_equal 1, @event.reload.notified_revision, "two guests already linked were never told about revisions 2 and 3"
    assert unsent.reload.token_digest.present?

    @event.guests.where.not(id: unsent.id).update_all(token_digest: nil)
    MailDelivery.invitation.delete_all
    Deliveries.invitation!(event: @event, guest: unsent, organizer: @organizer, request_ip: "203.0.113.1")
    assert_equal 3, @event.reload.notified_revision, "the only linked guest now knows the current state"

    @event.update_columns(revision: 4)
    MailDelivery.invitation.delete_all
    Deliveries.invitation!(event: @event, guest: @guest, organizer: @organizer, request_ip: "203.0.113.1")
    assert_equal 3, @event.reload.notified_revision, "a late invitee does not hide what the first guest was never told"
  end

  test "reopened! tells every active linked guest once by the claim rule, the organizer not at all, and marks the revision told" do
    @event.update_columns(revision: 5, notified_revision: 2)
    pending = participants(:planning_pending)
    stale = pending.issue_pending_token!
    window = [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ]

    told = nil
    assert_difference "MailDelivery.reopened.count", 2 do
      assert_enqueued_jobs 2, only: MailDeliveryJob do
        told = Deliveries.reopened!(event: @event, previous_window: window)
      end
    end

    assert_equal 2, told
    rows = MailDelivery.reopened.order(:id)
    assert_equal %w[invitee@example.com pending@example.com], rows.map(&:recipient_email).sort
    assert rows.all? { |row| row.sender_email == "owner@example.com" && row.participant_id.present? && row.request_ip.nil? }
    assert_equal 5, @event.reload.notified_revision
    pending.reload
    assert pending.pending_token_digest.present?
    assert_not_equal Participant.digest(stale), pending.pending_token_digest, "the previous pending token retires"
    assert_nil pending.pending_token_expires_at
    assert_equal Participant.digest(raw_token(:planning_pending)), pending.token_digest, "the live token keeps working"
    assert_nil @guest.reload.pending_token_digest, "a claimed guest gets no token"
    assert_nil @organizer.reload.pending_token_digest

    perform_enqueued_jobs
    mails = ActionMailer::Base.deliveries.last(2).index_by { |mail| mail.to.first }
    assert_equal [ "Catching App: Planning session is no longer set for Tue 15 Jan" ], mails.values.map(&:subject).uniq
    pending_body = mails["pending@example.com"].text_part.body.to_s
    assert_match %r{http://example.com/p/[A-Za-z0-9]{32}}, pending_body
    assert_not_includes pending_body, raw_token(:planning_pending), "never the live token"
    assert_not_includes pending_body, stale
    claimed_body = mails["invitee@example.com"].text_part.body.to_s
    assert_includes claimed_body, "http://example.com/participations/#{@guest.id}"
    assert_not_includes claimed_body, "/p/"
    mails.each_value do |mail|
      assert_includes mail.text_part.body.to_s, "Tue 15 Jan 2030 10:00–11:00 (UTC)"
      assert_includes mail.attachments.first.body.decoded, "STATUS:CANCELLED"
      assert_includes mail.attachments.first.body.decoded, "SEQUENCE:5"
    end
    assert MailDelivery.reopened.all? { |row| row.reload.delivered_at.present? }
  end

  test "finalized! is never capped" do
    10.times do |i|
      MailDelivery.create!(event: events(:other_event), kind: :invitation, recipient_email: @guest.email,
        sender_email: "f#{i}@example.com")
    end

    assert_difference "MailDelivery.finalized.count", 2 do
      Deliveries.finalized!(event: events(:finalized))
    end
    assert MailDelivery.finalized.exists?(recipient_email: "invitee@example.com")
  end

  test "reopened! is never capped and prints the window from the job's own params" do
    10.times do |i|
      MailDelivery.create!(event: events(:other_event), kind: :invitation, recipient_email: @guest.email,
        sender_email: "o#{i}@example.com")
    end
    finalized = events(:finalized)
    window = finalized.reopen!

    perform_enqueued_jobs do
      assert_difference "MailDelivery.reopened.where(recipient_email: 'invitee@example.com').count", 1 do
        assert_equal 1, Deliveries.reopened!(event: finalized, previous_window: window)
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "invitee@example.com" ], mail.to
    assert_includes mail.text_part.body.to_s, "Finalized event is no longer set for Tue 15 Jan 2030 10:00–11:00 (UTC)."
    assert_includes mail.attachments.first.body.decoded, "DTSTART:20300115T100000Z"
    assert_equal 0, MailDelivery.reopened.where(recipient_email: "owner@example.com").count, "no organizer copy"
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

  test "event_updated! refuses an organizer who has not opened their link, and an unknown reason, writing nothing" do
    @organizer.update_columns(link_opened_at: nil)
    error = assert_raises(ArgumentError) do
      Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :all)
    end
    assert_equal "Open your organizer link before emailing guests", error.message

    @organizer.update_columns(link_opened_at: Time.current)
    assert_raises(ArgumentError) { Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :plan) }
    assert_equal 0, MailDelivery.event_updated.count
    assert_nil participants(:planning_pending).reload.pending_token_digest
  end

  test "event_updated! for details reaches every active linked guest by the claim rule and marks the revision told" do
    @event.update_columns(revision: 3, notified_revision: 1, place: "Zoom")
    pending = participants(:planning_pending)
    stale = pending.issue_pending_token!

    result = nil
    assert_difference "MailDelivery.event_updated.count", 2 do
      assert_enqueued_jobs 2, only: MailDeliveryJob do
        result = Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: "203.0.113.5", reason: :details,
          changes: { "place" => [ nil, "Zoom" ] })
      end
    end

    assert_equal({ sent: 2, skipped: 0 }, result)
    rows = MailDelivery.event_updated.order(:id)
    assert_equal %w[invitee@example.com pending@example.com], rows.map(&:recipient_email).sort
    assert rows.all? { |row| row.sender_email == "owner@example.com" && row.request_ip == "203.0.113.5" && row.participant_id.present? }
    assert_equal 3, @event.reload.notified_revision
    pending.reload
    assert pending.pending_token_digest.present?
    assert_not_equal Participant.digest(stale), pending.pending_token_digest, "the previous pending token retires"
    assert_nil pending.pending_token_expires_at
    assert_equal Participant.digest(raw_token(:planning_pending)), pending.token_digest, "the live token keeps working"
    assert_nil @guest.reload.pending_token_digest, "a claimed guest gets no token"
    assert_nil @organizer.reload.pending_token_digest

    perform_enqueued_jobs
    mails = ActionMailer::Base.deliveries.last(2).index_by { |mail| mail.to.first }
    assert_equal [ "Catching App: Olivia Owner changed Planning session" ], mails.values.map(&:subject).uniq
    pending_body = mails["pending@example.com"].text_part.body.to_s
    assert_match %r{http://example.com/p/[A-Za-z0-9]{32}}, pending_body
    assert_not_includes pending_body, raw_token(:planning_pending), "never the live token"
    assert_not_includes pending_body, stale
    assert_includes pending_body, "Olivia Owner changed the details of Planning session."
    assert_includes pending_body, "Where: Zoom"
    claimed_body = mails["invitee@example.com"].text_part.body.to_s
    assert_includes claimed_body, "http://example.com/participations/#{@guest.id}"
    assert_not_includes claimed_body, "/p/"
    assert MailDelivery.event_updated.all? { |row| row.reload.delivered_at.present? }
  end

  test "event_updated! for an offer change reaches replied guests only and skips declined guests when nothing was added" do
    pending = participants(:planning_pending)
    @event.update_columns(offer_revised_at: Time.current, offer_revision_added: 0, offer_revision_removed: 2)

    assert_difference "MailDelivery.event_updated.count", 1 do
      Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :offer)
    end
    assert_equal [ "invitee@example.com" ], MailDelivery.event_updated.pluck(:recipient_email), "the unreplied guest hears nothing"

    MailDelivery.event_updated.delete_all
    @guest.update_columns(declined_at: Time.current)
    assert_equal({ sent: 0, skipped: 0 }, Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :offer))

    @event.update_columns(offer_revision_added: 1)
    pending.update_columns(responded_at: Time.current)
    result = nil
    assert_difference "MailDelivery.event_updated.count", 2 do
      result = Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :offer)
    end
    assert_equal({ sent: 2, skipped: 0 }, result)
    assert_equal %w[invitee@example.com pending@example.com], MailDelivery.event_updated.pluck(:recipient_email).sort

    assert_equal({ sent: 0, skipped: 2 }, Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :offer),
      "inside the cooldown both are skipped")
  end

  test "event_updated! skips capped recipients without a row and marks the revision told only when something was sent" do
    @event.update_columns(revision: 2, notified_revision: 0)
    5.times do |i|
      MailDelivery.create!(event: @event, participant: @guest, kind: :event_updated, recipient_email: @guest.email,
        sender_email: "owner@example.com", created_at: (i + 1).hours.ago)
    end

    result = nil
    assert_difference "MailDelivery.event_updated.count", 1 do
      result = Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :all)
    end
    assert_equal({ sent: 1, skipped: 1 }, result)
    assert_equal [ "pending@example.com" ], MailDelivery.event_updated.where(created_at: 1.minute.ago..).pluck(:recipient_email)
    assert_equal 2, @event.reload.notified_revision

    @event.update_columns(revision: 3)
    assert_no_difference "MailDelivery.count" do
      result = Deliveries.event_updated!(event: @event, organizer: @organizer, request_ip: nil, reason: :all)
    end
    assert_equal({ sent: 0, skipped: 2 }, result)
    assert_equal 2, @event.reload.notified_revision, "nothing sent, nothing told"
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
      assert_includes mail.attachments.first.body.decoded, "STATUS:CANCELLED"
    end
    assert MailDelivery.cancelled.where(event: finalized).all? { |row| row.delivered_at.present? }

    @event.cancel!
    perform_enqueued_jobs { Deliveries.cancelled!(event: @event) }
    assert_not_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "It was set for"
    assert_empty ActionMailer::Base.deliveries.last.attachments
  end
end
