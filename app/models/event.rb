class Event < ApplicationRecord
  belongs_to :user
  has_many :time_slots
  has_many :user_events
  has_many :invited_users, through: :user_events, source: :user

  def invite(user)
    UserEvent.create(user: user, event: self)
  end
end
