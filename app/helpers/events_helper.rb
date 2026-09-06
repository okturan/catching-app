module EventsHelper
  DURATION_STEP = 15
  DURATION_TAIL = [ 300, 360, 480, 720, 1440 ].freeze
  PLAN_DURATIONS = [ 15, 30, 45, 60, 90, 120, 150, 180, 240 ].freeze

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

  # Every server-rendered instant on a capability page: ISO datetime for the
  # machine, wall clock and zone name for the reader. Pages with a zone
  # picker rewrite [data-zoned-instant] into the picker's zone.
  def zoned_time(instant, zone_name, format: "%H:%M")
    zone = ActiveSupport::TimeZone[zone_name.to_s] || ActiveSupport::TimeZone["UTC"]
    local = instant.in_time_zone(zone)
    tag.time("#{local.strftime(format)} (#{zone.name})", datetime: instant.utc.iso8601, class: "time", data: { zoned_instant: "" })
  end
end
