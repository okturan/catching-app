# One painted instant: the organizer's offer or a guest's availability. Slots
# are written in bulk, so the database carries the rules: the quarter hour,
# one row per participant and instant, and a participant of the same event.
class TimeSlot < ApplicationRecord
  belongs_to :participant
  belongs_to :event
end
