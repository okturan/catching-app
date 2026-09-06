module EventsHelper
  DURATION_STEP = 15
  DURATION_TAIL = [ 300, 360, 480, 720, 1440 ].freeze
  PLAN_DURATIONS = [ 15, 30, 45, 60, 90, 120, 150, 180, 240 ].freeze

  # Where each error on the planning form points. Base errors are the grid's:
  # with the invitee field gone, every ArgumentError this form can raise comes
  # from TimeSlotParser, replace_time_slots! or ensure_aligned!, so no message
  # is matched and none needs to be.
  ERROR_TARGETS = {
    name: "event_name",
    description: "event_description",
    place: "event_place",
    place_url: "event_place_url",
    duration_minutes: "event_duration_minutes",
    slot_minutes: "event_slot_minutes",
    time_zone: "timezone-picker-new"
  }.freeze

  # The two organizer fields are hand-rolled, not a form builder's, so their
  # messages carry the field's own label the way full_message would.
  ORGANIZER_ERROR_TARGETS = {
    name: [ "organizer_name", "Your name" ],
    email: [ "organizer_email", "Your email" ]
  }.freeze

  # One [message, control id] per error for the summary, in the page's order:
  # the grid first, then the fields, then the organizer. Attribute errors are
  # listed too, and must stay listed: event[time_zone] is a hand-rolled
  # select_tag with no inline error, so the summary is the only place its
  # message is ever said.
  def planning_error_links(event, organizer_errors)
    links = event.errors[:base].map { |message| [ message, "time-grid-define" ] }
    event.errors.each do |error|
      next if error.attribute == :base

      links << [ event.errors.full_message(error.attribute, error.message), ERROR_TARGETS[error.attribute] ]
    end
    organizer_errors.each do |attribute, message|
      id, label = ORGANIZER_ERROR_TARGETS.fetch(attribute)
      links << [ "#{label} #{message}", id ]
    end
    links
  end

  # SimpleForm 5.4.1 links neither its hint nor its error to the control, so
  # every field on the planning form says so itself: the hint always, the
  # error id and aria-invalid only once the server has rendered one.
  def planning_field_aria(event, attribute, hint_id, error_id, required: false)
    invalid = event.errors[attribute].any?
    aria = { describedby: [ hint_id, (error_id if invalid) ].compact.join(" ") }
    aria[:required] = true if required
    aria[:invalid] = true if invalid
    aria
  end

  # "1 h 30 min", "2 h", "45 min": a length, never a clock reading, so no zone.
  def duration_label(minutes)
    hours, rest = minutes.to_i.divmod(60)
    parts = []
    parts << "#{hours} h" if hours.positive?
    parts << "#{rest} min" if rest.positive?
    parts.join(" ")
  end

  # Every quarter hour up to four hours, then a few long stretches.
  def duration_choices
    (DURATION_STEP..240).step(DURATION_STEP).to_a + DURATION_TAIL
  end

  # Option tags for the planned-length select. Lengths that are not a whole
  # number of the step's slots are disabled, not hidden, so the definer can
  # enable them again when the organizer changes the step.
  def duration_select_options(slot_minutes, selected)
    step = slot_minutes.to_i
    disabled = step.positive? ? duration_choices.reject { |minutes| (minutes % step).zero? } : []
    options_for_select(duration_choices.map { |minutes| [ duration_label(minutes), minutes ] },
      selected: selected, disabled: disabled)
  end

  # Lengths offered for one plan item; an item that already has another
  # length keeps it in the list so saving the row never clears it.
  def plan_duration_options(selected)
    choices = (PLAN_DURATIONS | [ selected ].compact).sort
    options_for_select(choices.map { |minutes| [ duration_label(minutes), minutes ] }, selected)
  end

  # "Pizza · 30 min", or the name alone when the item has no length.
  def plan_item_label(activity)
    return activity.name if activity.duration.nil?

    "#{activity.name} · #{duration_label(activity.duration)}"
  end

  # The one place a place link is rendered: an anchor on a value the model
  # validated as http(s) and the database check pinned. The visible text is
  # the host, so the reader knows where the tab is going.
  def place_link(event)
    tag.a(href: event.place_url, class: "quiet-link", target: "_blank", rel: "noopener noreferrer nofollow") do
      safe_join([ URI.parse(event.place_url).host, " ", tag.span("(opens in a new tab)", class: "visually-hidden") ])
    end
  end

  # The two shapes a zoned instant takes: a clock reading, or a full date
  # with the clock. The JavaScript formatter (zonedLabel) knows the same two.
  ZONED_FORMATS = { time: "%H:%M", date_time: "%a %-d %b %Y %H:%M" }.freeze

  # Every server-rendered instant on a capability page: ISO datetime for the
  # machine, wall clock and zone name for the reader. Pages with a zone
  # picker rewrite [data-zoned-instant] into the picker's zone; an element
  # that carries a date announces it with data-zoned-format="date-time" so
  # the rewrite keeps the date.
  def zoned_time(instant, zone_name, format: :time)
    zone = ActiveSupport::TimeZone[zone_name.to_s] || ActiveSupport::TimeZone["UTC"]
    local = instant.in_time_zone(zone)
    data = { zoned_instant: "" }
    data[:zoned_format] = format.to_s.dasherize unless format == :time
    tag.time("#{local.strftime(ZONED_FORMATS.fetch(format))} (#{zone.name})", datetime: instant.utc.iso8601, class: "time", data: data)
  end
end
