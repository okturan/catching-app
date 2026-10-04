require "test_helper"

class EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "the emailed link confirms the address" do
    user = users(:owner)
    get email_confirmation_path(user.generate_token_for(:email_confirmation))

    assert_redirected_to new_session_path
    assert user.reload.email_confirmed?
  end

  test "a bad link confirms nothing" do
    get email_confirmation_path("nope")
    assert_redirected_to root_path
  end

  test "signing up sends the welcome mail" do
    assert_enqueued_emails 1 do
      post registration_path, params: { user: { first_name: "Ada", last_name: "Lovelace", email: "ada@example.com",
        password: "a long enough password", password_confirmation: "a long enough password" } }
    end
  end
end
