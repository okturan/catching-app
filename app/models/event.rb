class Event < ApplicationRecord
  belongs_to :user
  has_many :time_slots
end
