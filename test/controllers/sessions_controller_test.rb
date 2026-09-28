require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple".freeze

  test "signing in lands on the dashboard, or on the page that asked for it" do
    post session_path, params: { email: " Owner@Example.com ", password: PASSWORD }
    assert_redirected_to dashboard_url

    delete session_path
    get edit_account_path
    assert_redirected_to new_session_path
    post session_path, params: { email: "owner@example.com", password: PASSWORD }
    assert_redirected_to edit_account_url
  end

  test "a failed sign-in keeps the address, never says which half was wrong, and answers 422" do
    post session_path, params: { email: "owner@example.com", password: "wrong" }
    assert_response :unprocessable_entity
    assert_select "input#email[value=?]", "owner@example.com"
    assert_select ".alert", text: /Try another email address or password/

    post session_path, params: { email: "nobody@example.com", password: PASSWORD }
    assert_response :unprocessable_entity
    assert_select ".alert", text: /Try another email address or password/
  end

  test "signing out ends this browser's session and no other" do
    sign_in users(:owner)
    elsewhere = users(:owner).sessions.create!

    delete session_path
    assert_redirected_to root_path
    get dashboard_path
    assert_redirected_to new_session_path
    assert Session.exists?(elsewhere.id)
  end

  # Turbo sends Sign out as a real DELETE, and a browser repeats that method
  # on a 302; only a 303 lands on the sign-in page.
  test "signing out after the session is gone answers 303" do
    delete session_path

    assert_response :see_other
    assert_redirected_to new_session_path
  end

  test "sign-in attempts are rate limited" do
    with_rate_limit_count(11) do
      post session_path, params: { email: "owner@example.com", password: PASSWORD }
    end

    assert_redirected_to new_session_path
    assert_equal "Too many attempts. Try again in a few minutes.", flash[:alert]
  end
end
