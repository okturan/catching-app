class Activity < ApplicationRecord
  belongs_to :event, inverse_of: :activities

  validates :name, :description, presence: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }
end
