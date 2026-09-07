# One item of an event's plan. Items read in (position, id) order; the move
# action keeps positions dense, the model only requires them non-negative.
class Activity < ApplicationRecord
  MAX_PER_EVENT = 20

  belongs_to :event, inverse_of: :activities

  normalizes :name, with: ->(name) { name.squish }
  normalizes :description, with: ->(description) { description.strip.presence }

  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 500 }
  validates :duration, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1440 }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :plan_size, on: :create

  private

  def plan_size
    return unless event && event.activities.count >= MAX_PER_EVENT

    errors.add(:base, "The plan can have at most #{MAX_PER_EVENT} items")
  end
end
