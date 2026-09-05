require "application_system_test_case"

class OrganizerPlansEventTest < ApplicationSystemTestCase
  test "a visitor without an account plans an event and opens the organizer link" do
    visit root_path
    click_link "Plan a meeting", match: :first
    assert_current_path new_event_path

    fill_in "Name", with: "Board games night"
    fill_in "Description", with: "Bring snacks"
    fill_in "Your name", with: "Ann Organizer"
    fill_in "Your email (we send your organizer link there)", with: "ann@example.com"
    fill_in "Invite people (one address per line or comma-separated)", with: "bob@example.com"
    assert_select "Slot length", selected: "30 minutes"

    assert_selector "#time-grid-define .slot[data-date]", minimum: 24
    first_cell = find('#time-grid-define .slot[data-row="20"][data-col="1"]')
    second_cell = find('#time-grid-define .slot[data-row="21"][data-col="1"]')
    page.driver.browser.action.move_to(first_cell.native).pointer_down.move_to(second_cell.native).pointer_up.perform
    assert_text "2 slots on 1 day"

    click_button "Send me my organizer link"
    assert_text "Check your inbox"
    assert_text "ann@example.com"
    assert_text "Nothing has gone to your guests yet"

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "ann@example.com" ], mail.to
    link = mail.text_part.body.to_s[%r{http://[^\s]+/p/[A-Za-z0-9]{32}}]
    visit URI.parse(link).request_uri

    assert_text "No replies yet"
    assert_selector "input[type=submit][value='Send 1 invitation']"
    assert_equal 1, Event.find_by(name: "Board games night").guests.count
  end
end
