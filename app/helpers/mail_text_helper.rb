module MailTextHelper
  # Organizer-supplied text never carries a clickable URL into a mail.
  def mail_safe(text)
    text.to_s.gsub(%r{[a-z][a-z0-9+.\-]*://}i, "").squish
  end

  def zone_named(name)
    ActiveSupport::TimeZone[name.to_s] || ActiveSupport::TimeZone["UTC"]
  end

  def window_in(zone_name, start_time, end_time)
    zone = zone_named(zone_name)
    "#{start_time.in_time_zone(zone).strftime('%a %-d %b %Y %H:%M')}–#{end_time.in_time_zone(zone).strftime('%H:%M')} (#{zone.name})"
  end

  # Coalesces instants into per-day ranges: { "Tue 10 Feb 2031" => ["09:00–10:30", ...] }
  def coalesced_ranges(instants, slot_minutes, zone_name, max_days: 10)
    zone = zone_named(zone_name)
    step = slot_minutes.minutes
    ranges = instants.sort.each_with_object([]) do |instant, acc|
      if acc.any? && acc.last[1] == instant
        acc.last[1] = instant + step
      else
        acc << [ instant, instant + step ]
      end
    end

    by_day = ranges.group_by { |start, _finish| start.in_time_zone(zone).strftime("%a %-d %b %Y") }
    listed = by_day.first(max_days).to_h do |day, day_ranges|
      [ day, day_ranges.map { |start, finish| "#{start.in_time_zone(zone).strftime('%H:%M')}–#{finish.in_time_zone(zone).strftime('%H:%M')}" } ]
    end
    { days: listed, more: [ by_day.size - max_days, 0 ].max, zone: zone.name }
  end
end
