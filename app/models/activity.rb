class Activity < ApplicationRecord
  belongs_to :event
  validates :name, presence: true
  validates :duration, numericality: { only_integer: true }
end
