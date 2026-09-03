require "test_helper"

class ActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:planning)
    @activity = activities(:planning_activity)
  end

  test "organizer adds an activity to their event" do
    sign_in users(:owner)

    assert_difference "@event.activities.count", 1 do
      post event_activities_path(@event), params: { activity: { name: "Lunch", description: "Eat together", duration: 60 } }
    end

    assert_redirected_to event_activity_path(@event, @event.activities.order(:id).last)
  end

  test "organizer views the nested activity form and the index with the add control" do
    sign_in users(:owner)

    get new_event_activity_path(@event)
    assert_response :success
    assert_select "form[action=?]", event_activities_path(@event)

    get event_activities_path(@event)
    assert_select "a[href=?]", new_event_activity_path(@event)
    assert_select "a[href=?]", my_participation_path(participants(:planning_organizer))
  end

  test "invalid activity renders the form without persisting" do
    sign_in users(:owner)

    assert_no_difference "Activity.count" do
      post event_activities_path(@event), params: { activity: { name: "", description: "", duration: 0 } }
    end

    assert_response :unprocessable_entity
  end

  test "an invited account views but cannot add" do
    sign_in users(:invitee)

    get event_activities_path(@event)
    assert_response :success
    assert_select "a[href=?]", new_event_activity_path(@event), count: 0

    get event_activity_path(@event, @activity)
    assert_response :success

    post event_activities_path(@event), params: { activity: { name: "No", description: "no", duration: 30 } }
    assert_response :not_found
  end

  test "an unrelated account is not found" do
    sign_in users(:outsider)

    get event_activities_path(@event)
    assert_response :not_found
  end
end
