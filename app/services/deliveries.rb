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
    # The first invitation of an event describes it as it stands, so the
    # guests it reaches know about every revision so far. A later invitee or
    # a Resend to one guest tells nobody else, so it must not hide a change
    # the guests already linked were never told about.
    mark_notified(event) if event.guests.active.linked.where.not(id: guest.id).none?
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

  # After finalize!: everyone active with a link, the organizer included as
  # a receipt, never capped. An unclaimed guest gets a fresh pending token
  # for the link in the mail (the Resend mechanism: the live token keeps
  # working, the previous pending one retires); a claimed guest is linked to
  # the signed-in page by the mailer; the organizer's copy carries no link.
  # The set window travels in the params so a retried job never reads the
  # row, and the batch marks the guests as told about this revision.
  def finalized!(event:)
    ensure_not_cancelled!(event)
    window = [ event.start_time, event.end_time ]
    event.participants.active.linked.find_each do |participant|
      raw_token = participant.guest? && !participant.claimed? ? participant.issue_pending_token! : nil
      delivery = record!(event: event, participant: participant, kind: :finalized, recipient_email: participant.email)
      enqueue(delivery, raw_token, window: window, sequence: event.revision)
    end
    mark_notified(event)
  end

  # One coalesced change notice, only when the organizer asks (the details
  # checkbox, the offer checkbox or Tell the guests). Recipients are active
  # linked guests; an offer notice goes only to guests who already replied,
  # and skips declined guests when nothing was added. Every recipient passes
  # the notice caps or is skipped and counted; the link follows the claim
  # rule (a fresh pending token for an unclaimed guest, none for a claimed
  # one). The organizer never receives one. Returns { sent:, skipped: }.
  NOTICE_REASONS = %i[details offer all].freeze

  def event_updated!(event:, organizer:, request_ip:, reason:, changes: nil)
    ensure_not_cancelled!(event)
    raise ArgumentError, "Open your organizer link before emailing guests" if organizer.link_opened_at.blank?
    raise ArgumentError, "Unknown notice reason #{reason.inspect}" unless NOTICE_REASONS.include?(reason.to_s.to_sym)

    sent = 0
    skipped = 0
    notice_recipients(event, reason.to_s.to_sym).find_each do |guest|
      begin
        MailDelivery::Caps.check_update_notice!(event: event, organizer: organizer, recipient_email: guest.email, request_ip: request_ip)
      rescue MailDelivery::CapExceeded
        skipped += 1
        next
      end

      raw_token = guest.claimed? ? nil : guest.issue_pending_token!
      delivery = record!(event: event, participant: guest, kind: :event_updated, recipient_email: guest.email,
        sender_email: MailDelivery.canonical(organizer.email), request_ip: request_ip)
      enqueue(delivery, raw_token, reason: reason.to_s, changes: changes&.to_h)
      sent += 1
    end
    mark_notified(event) if sent.positive?
    { sent: sent, skipped: skipped }
  end

  def notice_recipients(event, reason)
    recipients = event.guests.active.linked
    return recipients unless reason == :offer

    recipients = recipients.where.not(responded_at: nil)
    event.offer_revision_added.zero? ? recipients.where(declined_at: nil) : recipients
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
      enqueue(delivery, nil, window: window, sequence: event.revision)
      told += 1
    end
    mark_notified(event)
    told
  end

  # After reopen!: every active linked guest hears once that the set time is
  # withdrawn, the organizer (who pressed the button) not at all. Never
  # capped: reopen! itself allows at most two per event. The link follows the
  # claim rule (a fresh pending token for an unclaimed guest, none for a
  # claimed one), the withdrawn window travels in the params so the job
  # prints it and builds the cancelled calendar file without reading the
  # row, and the batch marks the guests as told. Returns the number told.
  def reopened!(event:, previous_window:)
    ensure_not_cancelled!(event)
    organizer = event.organizer
    told = 0
    event.guests.active.linked.find_each do |guest|
      raw_token = guest.claimed? ? nil : guest.issue_pending_token!
      delivery = record!(event: event, participant: guest, kind: :reopened, recipient_email: guest.email,
        sender_email: organizer && MailDelivery.canonical(organizer.email))
      enqueue(delivery, raw_token, previous_window: previous_window, sequence: event.revision)
      told += 1
    end
    mark_notified(event)
    told
  end

  def record!(event:, participant:, kind:, recipient_email:, sender_email: nil, request_ip: nil)
    MailDelivery.create!(event: event, participant: participant, kind: kind, recipient_email: recipient_email,
      sender_email: sender_email, request_ip: request_ip)
  end

  def enqueue(delivery, raw_token, **extra)
    ParticipantMailer.with(delivery: delivery, token: raw_token, **extra).public_send(delivery.kind).deliver_later
  end

  # Monotonic: a batch enqueued from an older page must never lower the mark
  # and make "Tell the guests" reappear for changes everyone already heard.
  def mark_notified(event)
    Event.where(id: event.id).where(notified_revision: ...event.revision).update_all(notified_revision: event.revision)
    event.notified_revision = [ event.notified_revision, event.revision ].max
  end

  def ensure_not_cancelled!(event)
    raise Event::ClosedError, "This event was cancelled" if event.cancelled?
  end
end
