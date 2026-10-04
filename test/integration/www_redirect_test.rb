require "test_helper"

class WwwRedirectTest < ActionDispatch::IntegrationTest
  setup { @app_host = ENV["APP_HOST"] }
  teardown { ENV["APP_HOST"] = @app_host }

  test "www on the app's host redirects permanently to the bare domain, path and query kept" do
    ENV["APP_HOST"] = "catching.test"
    host! "www.catching.test"

    get "/events/new?from=mail"
    assert_response :moved_permanently
    assert_redirected_to "https://catching.test/events/new?from=mail"
  end

  test "without an app host nothing is redirected" do
    ENV.delete("APP_HOST")
    get root_path
    assert_response :success
  end
end
