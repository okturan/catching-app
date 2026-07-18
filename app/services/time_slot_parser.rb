require "time"

class TimeSlotParser
  MAX_DAYS = 31
  MAX_SLOTS = MAX_DAYS * 25
  MAX_RANGE = MAX_DAYS.days

  def self.call(value)
    values = value.to_s.split(",").compact_blank

    raise ArgumentError, "Select at least one time slot" if values.empty?
    raise ArgumentError, "Select no more than #{MAX_SLOTS} time slots" if values.size > MAX_SLOTS

    slots = values.map { |item| Time.iso8601(item).utc }.uniq.sort
    raise ArgumentError, "Time slots must fit within a 31-day window" if slots.last - slots.first > MAX_RANGE

    slots
  rescue ArgumentError => error
    raise error if error.message.start_with?("Select", "Time slots")

    raise ArgumentError, "Time slots must use ISO 8601 timestamps"
  end
end
