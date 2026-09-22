module EventsHelper
  DURATION_STEP = 15
  DURATION_TAIL = [ 300, 360, 480, 720, 1440 ].freeze
  PLAN_DURATIONS = [ 15, 30, 45, 60, 90, 120, 150, 180, 240 ].freeze

  # In the page's order: base errors belong to the grid, then the fields,
  # then the organizer's own. The zone's picker has no inline error, so the
  # summary is the only place its message appears.
  def definer_error_links(event, organizer: nil)
    grid, fields = event.errors.partition { it.attribute == :base }
    links = grid.map { [ it.message, "time-grid-define" ] } +
      fields.map { [ it.full_message, it.attribute == :time_zone ? "timezone-picker-new" : "event_#{it.attribute}" ] }
    links += organizer.errors.map { [ "Your #{it.attribute} #{it.message}", "organizer_#{it.attribute}" ] } if organizer
    links
  end

  def duration_choices
    (DURATION_STEP..240).step(DURATION_STEP).to_a + DURATION_TAIL
  end

  # Lengths that do not fit the step are disabled, not hidden, so a step
  # change can enable them again.
  def duration_select_options(slot_minutes, selected)
    step = slot_minutes.to_i
    disabled = step.positive? ? duration_choices.reject { |minutes| (minutes % step).zero? } : []
    options_for_select(duration_choices.map { |minutes| [ Length.new(minutes).to_s, minutes ] },
      selected: selected, disabled: disabled)
  end

  # An item's own length stays in the list, so saving the row never clears it.
  def plan_duration_options(selected)
    choices = (PLAN_DURATIONS | [ selected ].compact).sort
    options_for_select(choices.map { |minutes| [ Length.new(minutes).to_s, minutes ] }, selected)
  end

  # "Pizza · 30 min"
  def plan_item_label(item)
    [ item.name, item.length ].compact.join(" · ")
  end

  # The link text is the host, so the reader knows where the tab is going.
  def place_link(event)
    tag.a(href: event.place_url, class: "quiet-link", target: "_blank", rel: "noopener noreferrer nofollow") do
      safe_join([ URI.parse(event.place_url).host, " ", tag.span("(opens in a new tab)", class: "visually-hidden") ])
    end
  end

  # A zone picker rewrites every data-zoned-instant into its zone, keeping
  # the date when data-zoned-format says there is one.
  def zoned_time(instant, zone, format: :time)
    data = { zoned_instant: "" }
    data[:zoned_format] = format.to_s.dasherize unless format == :time
    tag.time("#{instant.in_time_zone(zone).to_fs(format)} (#{zone})", datetime: instant.utc.iso8601, class: "time", data:)
  end
end
