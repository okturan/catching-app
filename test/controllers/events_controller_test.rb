require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:owner)
    @invitee = users(:invitee)
    @outsider = users(:outsider)
    @event = events(:planning)
    @consensus_time = Time.zone.parse("2030-01-15 10:00:00")
  end

  test "organizer creates an event with invitations and availability atomically" do
    sign_in @owner
    first_time = Time.zone.parse("2031-02-10 09:00:00")
    second_time = first_time + 1.hour

    assert_difference({ "Event.count" => 1, "TimeSlot.count" => 2, "UserEvent.count" => 1 }) do
      post events_path, params: {
        event: {
          name: "Project kickoff",
          description: "Find a kickoff time",
          invited_user_ids: [ @invitee.id ]
        },
        time_slots: { time_slot_array: [ first_time, second_time ].map(&:iso8601).join(",") }
      }
    end

    created_event = Event.order(:id).last
    assert_redirected_to event_path(created_event)
    assert_equal @owner, created_event.user
    assert_equal [ @invitee ], created_event.invited_users.to_a
    assert_equal [ first_time, second_time ], created_event.time_slots.order(:start_time).pluck(:start_time)
  end

  test "invalid availability rolls back the complete event creation" do
    sign_in @owner

    assert_no_difference [ "Event.count", "TimeSlot.count", "UserEvent.count" ] do
      post events_path, params: {
        event: {
          name: "Broken event",
          description: "This must not persist",
          invited_user_ids: [ @invitee.id ]
        },
        time_slots: { time_slot_array: "not-an-iso8601-time" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "invitee can view an event" do
    sign_in @invitee

    get event_path(@event)

    assert_response :success
    assert_select "form[action=?]", event_time_slots_path(@event)
  end

  test "organizer can view the finalization form" do
    sign_in @owner

    get event_path(@event)

    assert_response :success
    assert_select "form[action=?]", event_path(@event)
  end

  test "new event form submits invitation ids expected by the controller" do
    sign_in @owner

    get new_event_path

    assert_response :success
    assert_select 'select[name="event[invited_user_ids][]"]'
  end

  test "outsider cannot view an event" do
    sign_in @outsider

    get event_path(@event)

    assert_response :not_found
  end

  test "invitee cannot finalize an event" do
    sign_in @invitee

    patch event_path(@event), params: {
      time_slots: { time_slot_array: @consensus_time.iso8601 }
    }

    assert_response :not_found
    assert_not @event.reload.status?
  end

  test "organizer finalizes a mutually available slot" do
    sign_in @owner

    patch event_path(@event), params: {
      time_slots: { time_slot_array: @consensus_time.iso8601 }
    }

    assert_redirected_to event_path(@event)
    @event.reload
    assert_predicate @event, :status?
    assert_equal @consensus_time, @event.start_time
    assert_equal @consensus_time + 1.hour, @event.end_time
  end

  test "organizer cannot finalize a slot without participant consensus" do
    sign_in @owner
    owner_only_time = Time.zone.parse("2030-01-15 11:00:00")

    patch event_path(@event), params: {
      time_slots: { time_slot_array: owner_only_time.iso8601 }
    }

    assert_response :see_other
    assert_redirected_to event_path(@event)
    assert_not @event.reload.status?
    assert_equal "Select only time slots available to every participant", flash[:alert]
  end

  test "organizer cannot finalize a discontinuous meeting window" do
    sign_in @owner
    later_time = Time.zone.parse("2030-01-15 12:00:00")
    @event.time_slots.create!(user: @owner, start_time: later_time)
    @event.time_slots.find_or_create_by!(user: @invitee, start_time: later_time)

    patch event_path(@event), params: {
      time_slots: { time_slot_array: [ @consensus_time, later_time ].map(&:iso8601).join(",") }
    }

    assert_response :see_other
    assert_not @event.reload.status?
    assert_equal "Select one continuous meeting window", flash[:alert]
  end

  test "organizer cannot finalize an event twice" do
    sign_in @owner
    finalized_event = events(:finalized)

    patch event_path(finalized_event), params: {
      time_slots: { time_slot_array: @consensus_time.iso8601 }
    }

    assert_response :see_other
    assert_redirected_to event_path(finalized_event)
    assert_equal "Availability is closed for this event", flash[:alert]
    assert_equal @consensus_time, finalized_event.reload.start_time
  end
end
