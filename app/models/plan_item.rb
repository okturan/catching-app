# One item of an event's plan, read in (position, id) order.
class PlanItem < ApplicationRecord
  PER_EVENT = 20

  belongs_to :event

  normalizes :name, with: -> { it.squish }
  normalizes :description, with: -> { it.strip.presence }

  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 500 }
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 24 * 60 }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :plan_has_room, on: :create

  def length
    Length.new(duration_minutes) if duration_minutes
  end

  private

  def plan_has_room
    errors.add(:base, "The plan can have at most #{PER_EVENT} items") if event.plan_items.count >= PER_EVENT
  end
end
