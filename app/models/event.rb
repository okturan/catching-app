class Event < ApplicationRecord
  belongs_to :user
  has_many :time_slots
  FRIENDS = User.all
end
