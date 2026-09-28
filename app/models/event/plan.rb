# The plan guests read on their card. Every write takes the lock, is refused
# once cancelled and bumps the revision; none mails anyone.
module Event::Plan
  extend ActiveSupport::Concern

  included do
    has_many :plan_items, -> { order(:position, :id) }, dependent: :delete_all
  end

  def add_plan_item!(attributes)
    revise_plan! { plan_items.create!(**attributes, position: next_plan_position) }
  end

  def update_plan_item!(item, attributes)
    revise_plan! { item.update!(attributes) }
  end

  def remove_plan_item!(item)
    revise_plan! { item.destroy! }
  end

  # The target is clamped to the plan, which is numbered densely again.
  def move_plan_item!(item, position)
    with_lock do
      ensure_not_cancelled!
      items = plan_items.reload.to_a
      from = items.index(item) or raise ActiveRecord::RecordNotFound
      target = position.clamp(0, items.size - 1)
      next if from == target

      items.insert(target, items.delete_at(from))
      items.each_with_index { |plan_item, index| plan_item.update_columns(position: index) unless plan_item.position == index }
      increment!(:revision)
    end
  end

  # Each item with its start: the set time plus the lengths before it, and
  # none after an item without a length. A mailer passes the start it was
  # queued with.
  def plan_timeline(from: nil)
    cursor = from || (start_time unless cancelled?)
    plan_items.map do |item|
      start = cursor
      cursor = (cursor + item.duration_minutes.minutes if cursor && item.duration_minutes)
      [ item, start ]
    end
  end

  def plan_minutes
    plan_items.sum { it.duration_minutes.to_i }
  end

  private

  def next_plan_position
    plan_items.maximum(:position)&.succ || 0
  end

  def revise_plan!
    with_lock do
      ensure_not_cancelled!
      yield.tap { increment!(:revision) }
    end
  end
end
