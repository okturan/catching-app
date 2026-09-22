# What the desktop and the phone system tests share.
#
# Two seconds is tight for parallel browsers; five keeps waits honest.
Capybara.default_max_wait_time = 5

module SystemTestHelper
  extend ActiveSupport::Concern

  included do
    include ActionMailer::TestHelper
    include ActionMailer::TestCase::ClearTestDeliveries

    setup { @browser_clock = share_the_clock_with_the_browser }
    teardown { page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @browser_clock) }
  end

  private

  # The server runs at the suite's pinned instant, so every page must too.
  # The page reads time only through Date.now (Luxon's clock), which starts
  # at the pinned instant on each load and ticks from there.
  def share_the_clock_with_the_browser
    pinned = (Time.current.to_r * 1000).to_i
    source = "Date.now = ((now, offset) => () => now() + offset)(Date.now, #{pinned} - Date.now())"
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source:).fetch("identifier")
  end

  # Signs in the way a person does, through the form.
  def sign_in(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "correct horse battery staple"
    click_button "Log in"
    assert_current_path dashboard_path
  end

  def hidden_value(selector)
    find(selector, visible: false).value
  end
end
