# Every transactional mail goes through here: caps are checked, the token is
# issued, the ledger row is written, and the mail is enqueued. Once an event
# is cancelled only cancelled! passes; every other kind raises, so no later
# action can put mail about a cancelled event in anyone's inbox.
module Deliveries
  module_function

  def invitation!(event:, guest:, organizer:, request_ip:)
    ensure_not_cancelled!(event)
    raise ArgumentError, "#{guest.email} left this event" if guest.left?

    MailDelivery::Caps.check_invitation!(event: event, organizer: organizer, recipient_email: guest.email, request_ip: request_ip)
    raw_token = guest.token_digest ? guest.issue_pending_token! : guest.issue_live_token!
    delivery = record!(event: event, participant: guest, kind: :invitation, recipient_email: guest.email,
      sender_email: MailDelivery.canonical(organizer.email), request_ip: request_ip)
    enqueue(delivery, raw_token)
    raw_token
  end

  def organizer_link!(event:, organizer:, request_ip:, pending: false)
    ensure_not_cancelled!(event)
    raw_token = pending ? organizer.issue_pending_token!(expires_in: 24.hours) : organizer.issue_live_token!
    delivery = record!(event: event, participant: organizer, kind: :organizer_link, recipient_email: organizer.email,
      request_ip: request_ip)
    enqueue(delivery, raw_token)
    raw_token
  end

  def response_confirmation!(event:, guest:)
    ensure_not_cancelled!(event)
    delivery = record!(event: event, participant: guest, kind: :response_confirmation, recipient_email: guest.email)
    enqueue(delivery, nil)
  end

  def finalized!(event:)
    ensure_not_cancelled!(event)
    event.participants.active.linked.find_each do |participant|
      delivery = record!(event: event, participant: participant, kind: :finalized, recipient_email: participant.email)
      enqueue(delivery, nil)
    end
  end

  def reveal_link!(event:, guest:, organizer:, request_ip:)
    ensure_not_cancelled!(event)
    raise ArgumentError, "#{guest.email} left this event" if guest.left?

    raw_token = guest.token_digest ? guest.issue_pending_token! : guest.issue_live_token!
    record!(event: event, participant: guest, kind: :link_shown, recipient_email: guest.email,
      sender_email: MailDelivery.canonical(organizer.email), request_ip: request_ip)
    raw_token
  end

  # The one last mail: everyone active with a link, declined guests and the
  # organizer included, left and never-invited excluded. No token, no link,
  # no cap. The set window, when there was one, travels in the params so a
  # retried job never reads the live row. Returns the number of people told.
  def cancelled!(event:)
    organizer = event.organizer
    window = event.status? ? [ event.start_time, event.end_time ] : nil
    told = 0
    event.participants.active.linked.find_each do |participant|
      delivery = record!(event: event, participant: participant, kind: :cancelled, recipient_email: participant.email,
        sender_email: organizer && MailDelivery.canonical(organizer.email))
      enqueue(delivery, nil, window: window)
      told += 1
    end
    event.update_columns(notified_revision: event.revision)
    told
  end

  def record!(event:, participant:, kind:, recipient_email:, sender_email: nil, request_ip: nil)
    MailDelivery.create!(event: event, participant: participant, kind: kind, recipient_email: recipient_email,
      sender_email: sender_email, request_ip: request_ip)
  end

  def enqueue(delivery, raw_token, **extra)
    ParticipantMailer.with(delivery: delivery, token: raw_token, **extra).public_send(delivery.kind).deliver_later
  end

  def ensure_not_cancelled!(event)
    raise Event::ClosedError, "This event was cancelled" if event.cancelled?
  end
end
