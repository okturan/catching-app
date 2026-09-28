require "test_helper"

class BrowserSupportTest < ActionDispatch::IntegrationTest
  OLD_SAFARI = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1 Safari/605.1.15".freeze

  test "an unsupported browser gets a real page, not a missing file" do
    get root_path, headers: { "HTTP_USER_AGENT" => OLD_SAFARI }

    assert_response :not_acceptable
    assert_select "#unsupported-browser"
    assert_match "reply to the invitation email", response.body
  end

  test "a supported browser passes" do
    get root_path, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" }

    assert_response :success
  end
end
