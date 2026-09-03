class TimeSlot < ApplicationRecord
  belongs_to :participant, inverse_of: :time_slots
  belongs_to :event, inverse_of: :time_slots

  before_validation { self.event_id ||= participant&.event_id }

  validates :start_time, presence: true
  validate :participant_is_on_event

  private

  # The composite foreign key is the real guarantee; this covers ad-hoc
  # callers before the database sees the row.
  def participant_is_on_event
    return if participant.nil? || participant.event_id == event_id

    errors.add(:participant, "belongs to another event")
  end
end
