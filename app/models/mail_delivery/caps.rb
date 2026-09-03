# Abuse limits counted from the ledger. All are best-effort under concurrency:
# two racing requests can exceed a cap by one, which is acceptable for an
# anti-abuse limit. Refusals raise CapExceeded with a generic message that
# never reveals whether an address is known.
module MailDelivery::Caps
  GENERIC_MESSAGE = "Could not send right now. Try again later.".freeze
  CREATION_MESSAGE = "Could not create the event right now. Try again later.".freeze

  INVITATION_DAILY_BUDGET = -> { Integer(ENV.fetch("INVITATION_DAILY_BUDGET", 500)) }
  RECIPIENTS_PER_ORGANIZER_PER_DAY = 100
  RECIPIENTS_PER_STARTER_ORGANIZER_PER_DAY = 20
  INVITATIONS_PER_IP_PER_DAY = 200
  INVITATIONS_PER_RECIPIENT_PER_DAY = 10
  INVITATIONS_PER_EVENT_ADDRESS = 5
  RESEND_COOLDOWN = 10.minutes
  OPENED_EVENTS_PER_ORGANIZER_PER_DAY = 5
  UNOPENED_EVENTS_PER_ADDRESS_PER_DAY = 3
  UNOPENED_EVENTS_PER_IP_PER_DAY = 10
  GUESTS_PER_EVENT = 50

  module_function

  # Raises when an invitation to `recipient_email` from `organizer` must not
  # be sent now. `request_ip` may be nil (jobs, console).
  def check_invitation!(event:, organizer:, recipient_email:, request_ip:)
    day = 24.hours.ago
    recipient = MailDelivery.canonical(recipient_email)
    sender = MailDelivery.canonical(organizer.email)
    invitations = MailDelivery.invitation

    if invitations.since(day).count >= INVITATION_DAILY_BUDGET.call
      Rails.logger.warn("MailDelivery::Caps: global invitation budget reached")
      raise MailDelivery::CapExceeded, GENERIC_MESSAGE
    end

    allowance = organizer_has_finalized?(organizer) ? RECIPIENTS_PER_ORGANIZER_PER_DAY : RECIPIENTS_PER_STARTER_ORGANIZER_PER_DAY
    raise MailDelivery::CapExceeded, GENERIC_MESSAGE if invitations.since(day).where(sender_email: sender).count >= allowance

    if request_ip.present? && invitations.since(day).where(request_ip: request_ip).count >= INVITATIONS_PER_IP_PER_DAY
      raise MailDelivery::CapExceeded, GENERIC_MESSAGE
    end

    if invitations.since(day).where(canonical_recipient_email: recipient).count >= INVITATIONS_PER_RECIPIENT_PER_DAY
      raise MailDelivery::CapExceeded, GENERIC_MESSAGE
    end

    per_address = invitations.where(event_id: event.id, canonical_recipient_email: recipient, failed_at: nil)
    raise MailDelivery::CapExceeded, "This address has received the maximum of #{INVITATIONS_PER_EVENT_ADDRESS} invitations for this event." if per_address.count >= INVITATIONS_PER_EVENT_ADDRESS

    last = per_address.order(created_at: :desc).first
    if last && last.created_at > RESEND_COOLDOWN.ago
      raise MailDelivery::CapExceeded, "Wait a few minutes before sending to this address again."
    end
  end

  # True when a recovery or organizer-link mail may go to `email` now.
  def organizer_link_allowed?(email)
    MailDelivery.organizer_link.since(1.hour.ago)
      .where(canonical_recipient_email: MailDelivery.canonical(email)).none?
  end

  # Raises when creating another event for `organizer_email` from `request_ip`
  # must be refused. Opened events count per address; unopened ones count per
  # IP and per (address, IP), so a third party cannot exhaust a victim from
  # another network.
  def check_event_creation!(organizer_email:, request_ip:)
    day = 24.hours.ago
    canonical = MailDelivery.canonical(organizer_email)
    recent = Participant.organizer.where(created_at: day..).pluck(:email, :link_opened_at)
      .select { |email, _opened| MailDelivery.canonical(email) == canonical }
    opened, unopened = recent.partition { |_email, opened_at| opened_at.present? }

    raise MailDelivery::CapExceeded, CREATION_MESSAGE if opened.size >= OPENED_EVENTS_PER_ORGANIZER_PER_DAY

    if request_ip.present?
      unopened_links = MailDelivery.organizer_link.since(day).where(request_ip: request_ip)
        .joins(:participant).merge(Participant.where(link_opened_at: nil))
      raise MailDelivery::CapExceeded, CREATION_MESSAGE if unopened_links.count >= UNOPENED_EVENTS_PER_IP_PER_DAY
      if unopened_links.where(canonical_recipient_email: canonical).count >= UNOPENED_EVENTS_PER_ADDRESS_PER_DAY
        raise MailDelivery::CapExceeded, CREATION_MESSAGE
      end
    end
    unopened
  end

  def organizer_has_finalized?(organizer)
    Participant.organizer.where(email: organizer.email).joins(:event).merge(Event.where(status: true)).exists?
  end
end
