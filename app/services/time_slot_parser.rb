require "time"

class TimeSlotParser
  MAX_DAYS = 31
  MAX_SLOTS = MAX_DAYS * 25
  MAX_RANGE = MAX_DAYS.days
  PAST_GRACE = 24.hours

  def self.max_slots(slot_minutes)
    MAX_SLOTS * (60 / slot_minutes)
  end

  def self.call(value, slot_minutes: 60)
    values = value.to_s.split(",").compact_blank
    limit = max_slots(slot_minutes)

    raise ArgumentError, "Select at least one time slot" if values.empty?
    raise ArgumentError, "Select no more than #{limit} time slots" if values.size > limit

    slots = values.map { |item| Time.iso8601(item).utc }.uniq.sort
    raise ArgumentError, "Time slots must fit within a 31-day window" if slots.last - slots.first > MAX_RANGE
    raise ArgumentError, "Select time slots from today onward" if slots.first < PAST_GRACE.ago

    slots
  rescue ArgumentError => error
    raise error if error.message.start_with?("Select", "Time slots")

    raise ArgumentError, "Time slots must use ISO 8601 timestamps"
  end
end
