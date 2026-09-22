# Mail text: organizer words without a clickable link, and every time with
# its zone named.
module MailTextHelper
  # Organizer-supplied text never carries a clickable URL into a mail. Also
  # MailTextHelper.mail_safe, for the calendar file a mail attaches.
  def mail_safe(text)
    text.to_s.gsub(%r{[a-z][a-z0-9+.\-]*://}i, "").squish
  end
  module_function :mail_safe

  # "Tue 15 Jan 2030 20:00–21:00 (Europe/Berlin)"
  def window_in(zone, start_time, end_time)
    "#{start_time.in_time_zone(zone).to_fs(:date_time)}–#{end_time.in_time_zone(zone).to_fs(:time)} (#{zone})"
  end

  # "20:00 (Europe/Berlin)"
  def clock_in(zone, instant)
    "#{instant.in_time_zone(zone).to_fs(:time)} (#{zone})"
  end

  # Painted instants as runs of touching slots, listed by local day:
  # { days: { "Tue 10 Feb 2031" => ["09:00–10:30"] }, more: 0, zone: "Europe/Berlin" }
  def coalesced_ranges(instants, slot_minutes, zone, max_days: 10)
    step = slot_minutes.minutes
    runs = instants.sort.slice_when { |earlier, later| later - earlier != step }
    by_day = runs.group_by { it.first.in_time_zone(zone).strftime("%a %-d %b %Y") }
    days = by_day.first(max_days).to_h do |day, day_runs|
      [ day, day_runs.map { "#{it.first.in_time_zone(zone).to_fs(:time)}–#{(it.last + step).in_time_zone(zone).to_fs(:time)}" } ]
    end
    { days:, more: [ by_day.size - max_days, 0 ].max, zone: }
  end
end
