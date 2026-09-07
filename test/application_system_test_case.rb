require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Warden::Test::Helpers
  include ActiveJob::TestHelper
  include ActionMailer::TestCase::ClearTestDeliveries

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end

  setup { Warden.test_mode! }
  teardown { Warden.test_reset! }

  private

  def hidden_value(selector)
    find(selector, visible: false).value
  end
end
