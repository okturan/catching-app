# Every transactional mail goes through here: caps are checked, the token is
# issued, the ledger row is written, and the mail is enqueued (from phase 3;
# until then the ledger is written and the raw token returned).
module Deliveries
  module_function

  def invitation!(event:, guest:, organizer:, request_ip:)
    raise ArgumentError, "#{guest.email} left this event" if guest.left?

    MailDelivery::Caps.check_invitation!(event: event, organizer: organizer, recipient_email: guest.email, request_ip: request_ip)
    raw_token = guest.token_digest ? guest.issue_pending_token! : guest.issue_live_token!
    delivery = record!(event: event, participant: guest, kind: :invitation, recipient_email: guest.email,
      sender_email: MailDelivery.canonical(organizer.email), request_ip: request_ip)
    enqueue(delivery, raw_token)
    raw_token
  end

  def organizer_link!(event:, organizer:, request_ip:, pending: false)
    raw_token = pending ? organizer.issue_pending_token!(expires_in: 24.hours) : organizer.issue_live_token!
    delivery = record!(event: event, participant: organizer, kind: :organizer_link, recipient_email: organizer.email,
      request_ip: request_ip)
    enqueue(delivery, raw_token)
    raw_token
  end

  def response_confirmation!(event:, guest:)
    delivery = record!(event: event, participant: guest, kind: :response_confirmation, recipient_email: guest.email)
    enqueue(delivery, nil)
  end

  def finalized!(event:)
    event.participants.active.linked.find_each do |participant|
      delivery = record!(event: event, participant: participant, kind: :finalized, recipient_email: participant.email)
      enqueue(delivery, nil)
    end
  end

  def reveal_link!(event:, guest:, organizer:, request_ip:)
    raise ArgumentError, "#{guest.email} left this event" if guest.left?

    raw_token = guest.token_digest ? guest.issue_pending_token! : guest.issue_live_token!
    record!(event: event, participant: guest, kind: :link_shown, recipient_email: guest.email,
      sender_email: MailDelivery.canonical(organizer.email), request_ip: request_ip)
    raw_token
  end

  def record!(event:, participant:, kind:, recipient_email:, sender_email: nil, request_ip: nil)
    MailDelivery.create!(event: event, participant: participant, kind: kind, recipient_email: recipient_email,
      sender_email: sender_email, request_ip: request_ip)
  end

  # Mail delivery arrives with ParticipantMailer in phase 3.
  def enqueue(delivery, raw_token)
    return unless defined?(ParticipantMailer)

    ParticipantMailer.with(delivery: delivery, token: raw_token).public_send(delivery.kind).deliver_later
  end
end
