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

    raise Refusal, "Select at least one time slot" if values.empty?
    raise Refusal, "Select no more than #{limit} time slots" if values.size > limit

    slots = values.map { parse(it) }.uniq.sort
    raise Refusal, "Time slots must fit within a 31-day window" if slots.last - slots.first > MAX_RANGE
    raise Refusal, "Select time slots from today onward" if slots.first < PAST_GRACE.ago

    slots
  end

  def self.parse(value)
    Time.iso8601(value).utc
  rescue ArgumentError
    raise Refusal, "Time slots must use ISO 8601 timestamps"
  end
  private_class_method :parse
end
