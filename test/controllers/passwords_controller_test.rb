require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "asking for a reset mails a known address and answers any other the same way" do
    assert_enqueued_emails 1 do
      post passwords_path, params: { email: "Owner@example.com" }
    end
    assert_redirected_to new_session_path
    answer = flash[:notice]

    assert_no_enqueued_emails do
      post passwords_path, params: { email: "nobody@example.com" }
    end
    assert_equal answer, flash[:notice]
  end

  test "a reset link sets a new password, signs out every browser and works once" do
    user = users(:owner)
    user.sessions.create!
    token = user.password_reset_token

    get edit_password_path(token)
    assert_response :success

    patch password_path(token), params: { user: { password: "a brand new passphrase", password_confirmation: "a brand new passphrase" } }
    assert_redirected_to new_session_path
    assert user.reload.authenticate("a brand new passphrase")
    assert_empty user.sessions

    get edit_password_path(token)
    assert_redirected_to new_password_path
  end

  test "a reset needs a password, and its link lasts an hour" do
    token = users(:owner).password_reset_token

    patch password_path(token), params: { user: { password: "", password_confirmation: "" } }
    assert_response :unprocessable_entity
    assert_select "#error-summary a[href='#user_password']", text: "Password can't be blank"

    travel 61.minutes
    get edit_password_path(token)
    assert_redirected_to new_password_path
    assert_match "invalid or has expired", flash[:alert]
  end
end
