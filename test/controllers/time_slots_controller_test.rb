require "test_helper"

class TimeSlotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:planning)
    @invitee = users(:invitee)
    @outsider = users(:outsider)
  end

  test "invitee replaces only their own availability" do
    sign_in @invitee
    replacement_times = [
      Time.zone.parse("2030-01-15 10:00:00"),
      Time.zone.parse("2030-01-15 11:00:00")
    ]
    owner_times = @event.time_slots.where(user: users(:owner)).order(:start_time).pluck(:start_time)

    post event_time_slots_path(@event), params: {
      time_slots: { time_slot_array: replacement_times.map(&:iso8601).join(",") }
    }

    assert_redirected_to event_path(@event)
    assert_equal replacement_times, @event.time_slots.where(user: @invitee).order(:start_time).pluck(:start_time)
    assert_equal owner_times, @event.time_slots.where(user: users(:owner)).order(:start_time).pluck(:start_time)
  end

  test "invalid replacement preserves existing availability" do
    sign_in @invitee
    existing_times = @event.time_slots.where(user: @invitee).order(:start_time).pluck(:start_time)

    post event_time_slots_path(@event), params: {
      time_slots: { time_slot_array: "invalid" }
    }

    assert_response :see_other
    assert_equal existing_times, @event.time_slots.where(user: @invitee).order(:start_time).pluck(:start_time)
  end

  test "invitee cannot submit a slot the organizer did not offer" do
    sign_in @invitee
    existing_times = @event.time_slots.where(user: @invitee).order(:start_time).pluck(:start_time)

    post event_time_slots_path(@event), params: {
      time_slots: { time_slot_array: Time.zone.parse("2030-01-20 09:00:00").iso8601 }
    }

    assert_response :see_other
    assert_equal existing_times, @event.time_slots.where(user: @invitee).order(:start_time).pluck(:start_time)
    assert_equal "Select only time slots offered by the organizer", flash[:alert]
  end

  test "outsider cannot submit availability" do
    sign_in @outsider

    assert_no_difference "TimeSlot.count" do
      post event_time_slots_path(@event), params: {
        time_slots: { time_slot_array: Time.zone.parse("2030-01-15 10:00:00").iso8601 }
      }
    end

    assert_response :not_found
  end

  test "invitee cannot modify a finalized event" do
    sign_in @invitee
    finalized_event = events(:finalized)
    existing_times = finalized_event.time_slots.where(user: @invitee).pluck(:start_time)

    post event_time_slots_path(finalized_event), params: {
      time_slots: { time_slot_array: Time.zone.parse("2030-01-15 11:00:00").iso8601 }
    }

    assert_response :see_other
    assert_redirected_to event_path(finalized_event)
    assert_equal "Availability is closed for this event", flash[:alert]
    assert_equal existing_times, finalized_event.time_slots.where(user: @invitee).pluck(:start_time)
  end
end
