require "test_helper"

class ActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:planning)
    @activity = activities(:planning_activity)
  end

  test "organizer adds an activity to their event" do
    sign_in users(:owner)

    assert_difference "@event.activities.count", 1 do
      post event_activities_path(@event), params: {
        activity: {
          name: "Lunch",
          description: "Eat together",
          duration: 60
        }
      }
    end

    created_activity = @event.activities.order(:id).last
    assert_redirected_to event_activity_path(@event, created_activity)
  end

  test "organizer views an activity from their event" do
    sign_in users(:owner)

    get event_activity_path(@event, @activity)

    assert_response :success
  end

  test "organizer views the nested activity form" do
    sign_in users(:owner)

    get new_event_activity_path(@event)

    assert_response :success
    assert_select "form[action=?]", event_activities_path(@event)
  end

  test "invalid activity renders the form without persisting" do
    sign_in users(:owner)

    assert_no_difference "Activity.count" do
      post event_activities_path(@event), params: {
        activity: { name: "", description: "", duration: 0 }
      }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]", event_activities_path(@event)
  end

  test "invitee cannot add an activity to another user's event" do
    sign_in users(:invitee)

    assert_no_difference "Activity.count" do
      post event_activities_path(@event), params: {
        activity: {
          name: "Unauthorized",
          description: "This should not be created",
          duration: 30
        }
      }
    end

    assert_response :not_found
  end

  test "outsider cannot view an activity from another user's event" do
    sign_in users(:outsider)

    get event_activity_path(@event, @activity)

    assert_response :not_found
  end
end
