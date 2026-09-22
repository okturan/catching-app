module EventsHelper
  DURATION_STEP = 15
  DURATION_TAIL = [ 300, 360, 480, 720, 1440 ].freeze
  PLAN_DURATIONS = [ 15, 30, 45, 60, 90, 120, 150, 180, 240 ].freeze

  # The planning form's summary, in the page's order: the grid's refusals
  # (base errors, since every refusal this form meets is about the painted
  # selection), then the fields, then the organizer's "Your name" and "Your
  # email". The zone is listed too and must stay listed: its picker is drawn
  # by hand without an inline error, so the summary is the only place its
  # message is ever said.
  def planning_error_links(event, organizer)
    grid, fields = event.errors.partition { it.attribute == :base }
    grid.map { [ it.message, "time-grid-define" ] } +
      fields.map { [ it.full_message, it.attribute == :time_zone ? "timezone-picker-new" : "event_#{it.attribute}" ] } +
      organizer.errors.map { [ "Your #{it.attribute} #{it.message}", "organizer_#{it.attribute}" ] }
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
