require "test_helper"

class PlanItemTest < ActiveSupport::TestCase
  setup do
    @event = events(:planning)
  end

  test "needs a name; duration and description are optional" do
    item = @event.plan_items.build(name: "  ", duration_minutes: nil, description: "   ")

    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
    assert_empty item.errors[:duration_minutes]
    assert_empty item.errors[:description]
    assert_nil item.description

    assert_predicate @event.plan_items.build(name: "Pizza"), :valid?
  end

  test "normalizes and bounds the text fields" do
    item = @event.plan_items.build(name: "  Pizza   first ", description: "  Order early.  ")

    assert_predicate item, :valid?
    assert_equal "Pizza first", item.name
    assert_equal "Order early.", item.description

    item.assign_attributes(name: "x" * 81, description: "y" * 501)
    assert_not item.valid?
    assert_includes item.errors[:name], "is too long (maximum is 80 characters)"
    assert_includes item.errors[:description], "is too long (maximum is 500 characters)"
  end

  test "a length is a whole number of minutes within one day, and the database refuses a non-positive one" do
    item = @event.plan_items.build(name: "Dune")

    [ 0, -5, 1441 ].each do |minutes|
      item.duration_minutes = minutes
      assert_not item.valid?, "#{minutes} must be refused"
    end
    item.duration_minutes = "90.5"
    assert_not item.valid?
    assert_includes item.errors[:duration_minutes], "must be an integer"
    [ 1, 1440 ].each do |minutes|
      item.duration_minutes = minutes
      assert_predicate item, :valid?, "#{minutes} must be accepted"
    end

    fixture = plan_items(:planning_plan_item)
    assert_raises(ActiveRecord::StatementInvalid) do
      PlanItem.transaction(requires_new: true) { fixture.update_columns(duration_minutes: 0) }
    end
    assert_nothing_raised { fixture.update_columns(duration_minutes: nil, description: nil) }
  end

  test "positions are non-negative at both layers and order the plan with id as the tie-break" do
    event = events(:other_event)
    late = event.plan_items.create!(name: "Late", position: 2)
    first = event.plan_items.create!(name: "First", position: 0)
    also_first = event.plan_items.create!(name: "Also first", position: 0)
    middle = event.plan_items.create!(name: "Middle", position: 1)

    assert_equal [ first, also_first, middle, late ], event.plan_items.reload.to_a

    assert_not event.plan_items.build(name: "Negative", position: -1).valid?
    assert_raises(ActiveRecord::StatementInvalid) do
      PlanItem.transaction(requires_new: true) { late.update_columns(position: -1) }
    end
  end

  test "the plan holds at most 20 items; existing items stay editable" do
    event = events(:other_event)
    20.times { |index| event.plan_items.create!(name: "Item #{index}", position: index) }

    extra = event.plan_items.build(name: "One more")
    assert_not extra.valid?
    assert_includes extra.errors[:base], "The plan can have at most 20 items"

    existing = event.plan_items.first
    existing.name = "Renamed"
    assert_predicate existing, :valid?
    assert_not events(:planning).plan_items.build(name: "Elsewhere").invalid?
  end

  test "items are deleted with their event at the database level" do
    event = events(:other_event)
    event.plan_items.create!(name: "Solo")

    Event.where(id: event.id).delete_all

    assert_equal 0, PlanItem.where(event_id: event.id).count
  end
end
