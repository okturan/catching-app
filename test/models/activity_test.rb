require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "requires descriptive fields and a positive duration" do
    activity = events(:planning).activities.build(duration: 0)

    assert_not activity.valid?
    assert_includes activity.errors[:name], "can't be blank"
    assert_includes activity.errors[:description], "can't be blank"
    assert_includes activity.errors[:duration], "must be greater than 0"
  end

  test "accepts a complete activity" do
    activity = events(:planning).activities.build(
      name: "Coffee",
      description: "Catch up over coffee",
      duration: 45
    )

    assert_predicate activity, :valid?
  end
end
