# One painted instant: the organizer's offer or a guest's availability. Slots
# are written in bulk, so the database carries the rules: the quarter hour,
# one row per participant and instant, and a participant of the same event.
class TimeSlot < ApplicationRecord
  MAX_DAYS = 31
  # A day has at most 25 hours, on the night the clocks go back.
  MAX_HOURS = MAX_DAYS * 25
  # A slot stays paintable for a day after it starts, so "today" covers every
  # zone on the planet.
  PAST_GRACE = 24.hours

  belongs_to :participant
  belongs_to :event

  # The instants of a painted selection, as the grid serializes it: comma
  # separated ISO 8601 times, deduplicated and in order.
  def self.parse(value, slot_minutes:)
    values = value.to_s.split(",").compact_blank
    limit = MAX_HOURS * 60 / slot_minutes
    raise Refusal, "Select at least one time slot" if values.empty?
    raise Refusal, "Select no more than #{limit} time slots" if values.size > limit

    instants = values.map { parse_instant(it) }.uniq.sort
    raise Refusal, "Time slots must fit within a #{MAX_DAYS}-day window" if instants.last - instants.first > MAX_DAYS.days
    raise Refusal, "Select time slots from today onward" if instants.first < PAST_GRACE.ago

    instants
  end

  def self.parse_instant(value)
    Time.iso8601(value).utc
  rescue ArgumentError
    raise Refusal, "Time slots must use ISO 8601 timestamps"
  end
  private_class_method :parse_instant
end
