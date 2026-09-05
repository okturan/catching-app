require "application_system_test_case"

class ClaimRoundTripTest < ApplicationSystemTestCase
  test "a guest signs up from their link and keeps the event in the new account" do
    pending = participants(:planning_pending)

    visit participation_path(raw_token(:planning_pending))
    click_link "Keep this event in your account"
    assert_text "Log in"

    within("main") { click_link "Sign up" }
    fill_in "First name", with: "Pat"
    fill_in "Last name", with: "Pending"
    fill_in "Email", with: "pat@example.com"
    fill_in "Password", with: "correct horse battery staple", match: :prefer_exact
    fill_in "Password confirmation", with: "correct horse battery staple"
    click_button "Sign up!"

    assert_text "Keep Planning session in your account"
    click_button "Keep this event in my account"
    assert_current_path my_participation_path(pending)
    assert_equal User.find_by(email: "pat@example.com"), pending.reload.user

    visit dashboard_path
    assert_text "Invited"
    assert_text "Planning session"
  end
end
