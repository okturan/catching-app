require "test_helper"

class EventSchedulingWorkflowTest < ActionDispatch::IntegrationTest
  test "organizer and invitee schedule a mutually available time" do
    owner = users(:owner)
    invitee = users(:invitee)
    first_time = Time.zone.parse("2032-03-20 14:00:00")
    second_time = first_time + 1.hour

    sign_in owner
    post events_path, params: {
      event: {
        name: "Catch up",
        description: "Schedule a call",
        invited_user_ids: [ invitee.id ]
      },
      time_slots: { time_slot_array: [ first_time, second_time ].map(&:iso8601).join(",") }
    }

    event = Event.order(:id).last
    assert_redirected_to event_path(event)

    sign_out owner
    sign_in invitee
    post event_time_slots_path(event), params: {
      time_slots: { time_slot_array: first_time.iso8601 }
    }
    assert_redirected_to event_path(event)

    sign_out invitee
    sign_in owner
    patch event_path(event), params: {
      time_slots: { time_slot_array: first_time.iso8601 }
    }
    assert_redirected_to event_path(event)

    event.reload
    assert_predicate event, :status?
    assert_equal first_time, event.start_time
    assert_equal first_time + 1.hour, event.end_time
  end
end
