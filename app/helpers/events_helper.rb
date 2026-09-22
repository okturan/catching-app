module EventsHelper
  DURATION_STEP = 15
  DURATION_TAIL = [ 300, 360, 480, 720, 1440 ].freeze
  PLAN_DURATIONS = [ 15, 30, 45, 60, 90, 120, 150, 180, 240 ].freeze

  # Where each error on the planning form points. Base errors are the grid's:
  # every refusal this form can meet is about the painted selection.
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
    options_for_select(duration_choices.map { |minutes| [ Length.new(minutes).to_s, minutes ] },
      selected: selected, disabled: disabled)
  end

  # Lengths offered for one plan item; an item that already has another
  # length keeps it in the list so saving the row never clears it.
  def plan_duration_options(selected)
    choices = (PLAN_DURATIONS | [ selected ].compact).sort
    options_for_select(choices.map { |minutes| [ Length.new(minutes).to_s, minutes ] }, selected)
  end

  # "Pizza · 30 min", or the name alone when the item has no length.
  def plan_item_label(item)
    [ item.name, item.length ].compact.join(" · ")
  end

  # The one place a place link is rendered: an anchor on a value the model
  # validated as http(s) and the database check pinned. The visible text is
  # the host, so the reader knows where the tab is going.
  def place_link(event)
    tag.a(href: event.place_url, class: "quiet-link", target: "_blank", rel: "noopener noreferrer nofollow") do
      safe_join([ URI.parse(event.place_url).host, " ", tag.span("(opens in a new tab)", class: "visually-hidden") ])
    end
  end

  # Every server-rendered instant on a capability page: ISO datetime for the
  # machine, wall clock and zone name for the reader, as :time or :date_time.
  # Pages with a zone picker rewrite [data-zoned-instant] into the picker's
  # zone, and the JavaScript formatter (zonedLabel) knows the same two
  # shapes; an element that carries a date says data-zoned-format="date-time"
  # so the rewrite keeps the date.
  def zoned_time(instant, zone, format: :time)
    data = { zoned_instant: "" }
    data[:zoned_format] = format.to_s.dasherize unless format == :time
    tag.time("#{instant.in_time_zone(zone).to_fs(format)} (#{zone})", datetime: instant.utc.iso8601, class: "time", data:)
  end
end
