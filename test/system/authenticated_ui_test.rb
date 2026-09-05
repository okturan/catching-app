require "application_system_test_case"

class AuthenticatedUiTest < ApplicationSystemTestCase
  test "owner signs in and reaches the event planner" do
    owner = users(:owner)

    visit new_user_session_path
    assert_text "Log in"

    fill_in "Email", with: owner.email
    fill_in "Password", with: "correct horse battery staple"
    click_button "Log in"

    assert_text "Sign out"
    assert_current_path dashboard_path
    assert_text "Planning session"
    assert_text "Organizing"
    click_link "Plan a meeting", match: :first

    assert_current_path new_event_path
    assert_field "Name"
    assert_field "Description"
    assert_field "Invite people (one address per line or comma-separated)"
    assert_select "Slot length", selected: "30 minutes"
    assert_selector "#timezone-picker-new option", minimum: 1
    assert_selector "#time-grid-define .slot", minimum: 1
    assert_button "Plan it"
  end
end
