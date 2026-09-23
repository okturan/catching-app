module ParticipantsHelper
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

  # "Deniz, Priya, and 2 others": the names guests gave, then a count of the
  # guests who have not given one.
  def also_invited(guests)
    names = guests.filter_map { it.name.presence }
    unnamed = guests.size - names.size
    return pluralize(unnamed, "guest") if names.empty?

    [ *names, (pluralize(unnamed, "other") if unnamed.positive?) ].compact.to_sentence
  end

  # A guest's reply first, then the fate of their last invitation.
  def guest_state_label(guest, invitations, slot_count:)
    last_invitation = invitations[guest.id]&.last
    state = guest_state(guest, last_invitation)
    label = STATE_LABELS.fetch(state)

    case state
    when :replied
      details = [ pluralize(slot_count, "slot"), ("before the last change" if guest.replied_before_revision?) ]
      "#{label} (#{details.compact.join(", ")})"
    when :delivered
      safe_join([ label, " on ", zoned_time(last_invitation.delivered_at, guest.event.time_zone, format: :date_time) ])
    else
      label
    end
  end

  # "Tue 15 Jan 20:00–21:00 (Europe/Berlin)", as the page's JavaScript prints it.
  def event_window(event)
    start_time, end_time = [ event.start_time, event.end_time ].map { it.in_time_zone(event.time_zone) }
    "#{start_time.to_fs(:day)} #{start_time.to_fs(:time)}–#{end_time.to_fs(:time)} (#{event.time_zone})"
  end

  private

  def guest_state(guest, last_invitation)
    return :left if guest.left?
    return :declined if guest.declined_at?
    return :needs_reply if guest.voided?
    return :replied if guest.responded_at?
    return :not_sent unless guest.token_digest?

    last_invitation ? last_invitation.state : :queued
  end
end
