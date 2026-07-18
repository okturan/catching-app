class UserEvent < ApplicationRecord
  belongs_to :user, inverse_of: :user_events
  belongs_to :event, inverse_of: :user_events

  validates :user_id, uniqueness: { scope: :event_id }
  validate :user_is_not_event_owner

  private

  def user_is_not_event_owner
    errors.add(:user, "cannot invite the event organizer") if event&.user_id == user_id
  end
end
