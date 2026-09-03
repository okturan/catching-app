module ParticipationsHelper
  STATE_LABELS = {
    left: "left",
    declined: "none of these work",
    replied: "replied",
    not_sent: "not sent",
    queued: "queued",
    unknown: "delivery unknown, resend",
    failed: "could not be delivered",
    delivered: "sent"
  }.freeze

  # Delivery and reply state of a guest for the organizer table.
  def guest_state(guest, deliveries)
    return :left if guest.left?
    return :declined if guest.declined_at.present?
    return :replied if guest.responded_at.present?
    return :not_sent if guest.token_digest.nil?

    last = (deliveries[guest.id] || []).last
    last ? last.state : :queued
  end

  def guest_state_label(guest, deliveries, slot_count: nil)
    state = guest_state(guest, deliveries)
    label = STATE_LABELS.fetch(state)
    label = "#{label} (#{pluralize(slot_count, 'slot')})" if state == :replied && slot_count
    last = (deliveries[guest.id] || []).last
    label = "#{label} on #{l(last.delivered_at, format: :short)}" if state == :delivered && last&.delivered_at
    label
  end

  def event_window(event, zone_name = event.time_zone)
    zone = ActiveSupport::TimeZone[zone_name] || ActiveSupport::TimeZone["UTC"]
    start_time = event.start_time.in_time_zone(zone)
    end_time = event.end_time.in_time_zone(zone)
    "#{start_time.strftime('%a %-d %b %H:%M')}–#{end_time.strftime('%H:%M')} (#{zone.name})"
  end
end
