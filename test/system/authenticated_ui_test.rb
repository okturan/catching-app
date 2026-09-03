require "application_system_test_case"

class AuthenticatedUiTest < ApplicationSystemTestCase
  test "owner signs in and reaches the event planner" do
    owner = users(:owner)

    visit new_user_session_path
    assert_text "Log in"

    fill_in "Email", with: owner.email
    fill_in "Password", with: "correct horse battery staple"
    click_button "Log in"

    assert_text "SIGN OUT"
    click_link "SEE MY EVENTS"

    assert_current_path dashboard_path
    assert_text "Planning session"
    click_link "PLAN YOUR MEETING NOW"

    assert_current_path new_event_path
    assert_field "Name"
    assert_field "Description"
    assert_selector "#event_invited_user_ids option", text: users(:invitee).full_name
    assert_selector "#timezone-picker-new option", minimum: 1
    assert_selector "#time-grid-define .slot", minimum: 1
    assert_button "Catch.App with your Friends!"
  end
end
