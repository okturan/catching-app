require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signing up creates the account, signs it in and lands on the dashboard" do
    assert_difference [ "User.count", "Session.count" ] do
      post registration_path, params: { user: { first_name: "Gwen", last_name: "Guest", email: "Gwen@Example.com",
        password: "correct horse battery staple", password_confirmation: "correct horse battery staple" } }
    end

    assert_redirected_to dashboard_url
    assert_equal "gwen@example.com", User.order(:id).last.email
    follow_redirect!
    assert_response :success
  end

  test "a failed sign-up lists every error in the form's order and answers 422" do
    assert_no_difference "User.count" do
      post registration_path, params: { user: { first_name: "", last_name: "", email: "Owner@example.com",
        password: "too short", password_confirmation: "something else" } }
    end

    assert_response :unprocessable_entity
    assert_equal [ "First name can't be blank", "Last name can't be blank", "Email has already been taken",
      "Password is too short (minimum is 15 characters)", "Password confirmation doesn't match Password" ],
      css_select("#error-summary li a").map(&:text)
    assert_select "#user_first_name[autofocus]", count: 0
  end
end
