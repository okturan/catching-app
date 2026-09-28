require "application_system_test_case"

class InviteeReadsDashboardTest < ApplicationSystemTestCase
  teardown { page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "") }

  test "the dashboard reads each event's time in the visitor's own zone" do
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "Asia/Tokyo")
    sign_in users(:invitee)

    assert_selector ".event-face", text: "Finalized event"
    assert_selector ".event-face-time time", text: "Tue 15 Jan 2030 19:00 (Asia/Tokyo)"
  end
end
