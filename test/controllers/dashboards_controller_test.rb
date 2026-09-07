require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "the dashboard lists participations and nobody else" do
    sign_in users(:owner)

    get dashboard_path

    assert_response :success
    assert_select "h2", /\AOrganizing/
    assert_select "a[href=?]", my_participation_path(participants(:planning_organizer))
    assert_select "a[href=?]", my_participation_path(participants(:finalized_organizer))
    assert_no_match "Uma Organizer", response.body
    assert_no_match "other-owner@example.com", response.body
    assert_no_match "Members", response.body
  end

  test "invited participations are listed under Invited and left ones are hidden" do
    sign_in users(:invitee)

    get dashboard_path
    assert_select "a[href=?]", my_participation_path(participants(:planning_guest))

    participants(:planning_guest).leave!
    get dashboard_path
    assert_select "a[href=?]", my_participation_path(participants(:planning_guest)), count: 0
  end

  test "a cancelled event stays listed and its card says cancelled in both sections" do
    events(:planning).cancel!
    sign_in users(:owner)

    get dashboard_path

    assert_select "a[href=?]", my_participation_path(participants(:planning_organizer)) do
      assert_select ".event-face-time", text: "cancelled"
      assert_select ".event-face-state", text: /cancelled/
      assert_select ".event-face-state", text: /3 guests/
    end
    assert_select "a[href=?]", my_participation_path(participants(:finalized_organizer)) do
      assert_select ".event-face-time", text: /15 Jan/
      assert_select ".event-face-state", text: /cancelled/, count: 0
    end

    sign_in users(:invitee)
    get dashboard_path
    assert_select "a[href=?] .event-face-state", my_participation_path(participants(:planning_guest)), text: /cancelled/
    assert_select "a[href=?] .event-face-time", my_participation_path(participants(:planning_guest)), text: "cancelled"
    assert_select "a[href=?] .event-face-state", my_participation_path(participants(:finalized_guest)), text: /cancelled/, count: 0
  end

  test "sign-in lands on the dashboard" do
    post user_session_path, params: { user: { email: "owner@example.com", password: "correct horse battery staple" } }

    assert_redirected_to dashboard_path
  end
end
