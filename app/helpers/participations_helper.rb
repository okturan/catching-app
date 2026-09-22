module ParticipationsHelper
  STATE_LABELS = {
    left: "left",
    declined: "none of these work",
    replied: "replied",
    needs_reply: "needs a new reply",
    not_sent: "not sent",
    queued: "queued",
    unknown: "delivery unknown, resend",
    failed: "could not be delivered",
    delivered: "sent"
  }.freeze

  # Delivery and reply state of a guest for the organizer table. A voided
  # guest replied, but an offer revision took every pick away.
  def guest_state(guest, deliveries)
    return :left if guest.left?
    return :declined if guest.declined_at.present?
    return :needs_reply if guest.voided?
    return :replied if guest.responded_at.present?
    return :not_sent if guest.token_digest.nil?

    last = (deliveries[guest.id] || []).last
    last ? last.state : :queued
  end

  def guest_state_label(guest, deliveries, slot_count: nil)
    state = guest_state(guest, deliveries)
    label = STATE_LABELS.fetch(state)
    if state == :replied && slot_count
      detail = pluralize(slot_count, "slot")
      detail += ", before the last change" if guest.replied_before_revision?
      label = "#{label} (#{detail})"
    end
    last = (deliveries[guest.id] || []).last
    label = "#{label} on #{l(last.delivered_at, format: :short)}" if state == :delivered && last&.delivered_at
    label
  end

  # "Tue 15 Jan 20:00–21:00 (Europe/Berlin)", the way the page's JavaScript
  # prints the set time.
  def event_window(event)
    start_time, end_time = [ event.start_time, event.end_time ].map { it.in_time_zone(event.time_zone) }
    "#{start_time.to_fs(:day)} #{start_time.to_fs(:time)}–#{end_time.to_fs(:time)} (#{event.time_zone})"
  end
end
