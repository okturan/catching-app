require "test_helper"

class LoginLinksControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "asking sends a link only to a known address and never says which" do
    assert_enqueued_emails 1 do
      post login_links_path, params: { email: " Owner@Example.com " }
    end
    assert_redirected_to new_session_path

    assert_enqueued_emails 0 do
      post login_links_path, params: { email: "nobody@example.com" }
    end
    assert_equal "If that address has an account, a login link is on its way. It works for 15 minutes.", flash[:notice]
  end

  test "the link logs in once, confirms the address, and is refused the second time" do
    user = users(:owner)
    token = user.generate_token_for(:login)

    get login_link_path(token)
    assert_redirected_to dashboard_url
    assert user.reload.email_confirmed?

    delete session_path
    get login_link_path(token)
    assert_redirected_to new_login_link_path
  end
end
