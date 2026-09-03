require "test_helper"

class ForgeryProtectionTest < ActionDispatch::IntegrationTest
  setup do
    @previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous
  end

  test "a token-route write without an authenticity token is rejected" do
    guest = participants(:planning_guest)
    before = guest.time_slots.order(:start_time).pluck(:start_time)

    patch participation_path(raw_token(:planning_guest)), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }

    assert_response :unprocessable_entity
    assert_equal before, guest.time_slots.reload.order(:start_time).pluck(:start_time)
  end
end
