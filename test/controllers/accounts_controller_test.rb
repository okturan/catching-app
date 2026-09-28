require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple".freeze

  setup { @owner = users(:owner) }

  test "the account page asks who you are first" do
    get edit_account_path

    assert_redirected_to new_session_path
  end

  test "every change proves the current password" do
    sign_in @owner

    patch account_path, params: { user: { first_name: "Liv" } }
    assert_response :unprocessable_entity
    assert_select "#error-summary a[href='#user_password_challenge']", text: "Current password is invalid"
    assert_equal "Olivia", @owner.reload.first_name

    patch account_path, params: { user: { first_name: "Liv", password_challenge: PASSWORD } }
    assert_redirected_to edit_account_path
    assert_equal "Liv", @owner.reload.first_name
  end

  test "a blank new password keeps the old one, and a new one replaces it" do
    sign_in @owner

    patch account_path, params: { user: { password: "", password_confirmation: "", password_challenge: PASSWORD } }
    assert @owner.reload.authenticate(PASSWORD)

    patch account_path, params: { user: { password: "another long passphrase", password_confirmation: "another long passphrase", password_challenge: PASSWORD } }
    assert @owner.reload.authenticate("another long passphrase")
  end

  test "deleting the account signs out and leaves the events" do
    sign_in @owner

    delete account_path

    assert_redirected_to root_path
    assert_not User.exists?(@owner.id)
    assert_nil participants(:planning_organizer).reload.user_id
    get dashboard_path
    assert_redirected_to new_session_path
  end
end
