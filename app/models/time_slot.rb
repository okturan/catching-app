class TimeSlot < ApplicationRecord
  belongs_to :user, inverse_of: :time_slots
  belongs_to :event, inverse_of: :time_slots

  validates :start_time, presence: true,
    uniqueness: { scope: %i[user_id event_id] }
end
