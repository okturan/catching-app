require "application_system_test_case"

class OrganizerPlansEventTest < ApplicationSystemTestCase
  test "a visitor without an account plans an event and opens the organizer link" do
    visit root_path
    click_link "Plan a meeting", match: :first
    assert_current_path new_event_path

    fill_in "Name", with: "Board games night"
    fill_in "Description", with: "Bring snacks"
    fill_in "Your name", with: "Ann Organizer"
    fill_in "Your email", with: "ann@example.com"
    fill_in "Place", with: "Ege's place, Kadıköy"
    fill_in "Link", with: "https://zoom.us/j/1"
    assert_select "Slot length", selected: "30 minutes"

    assert_selector "#event_duration_minutes option[value='45']:disabled", visible: :all
    select "1 h 30 min", from: "Planned length"
    select "60 minutes", from: "Slot length"
    assert_selector "#event_duration_minutes option[value='90']:disabled", visible: :all
    assert_text "Planned length cleared: 1 h 30 min is not a whole number of 60-minute slots."
    assert_select "Planned length", selected: "Not set"
    select "30 minutes", from: "Slot length"
    assert_selector "#event_duration_minutes option[value='90']:enabled", visible: :all
    select "1 h 30 min", from: "Planned length"

    assert_selector "#time-grid-define .slot[data-date]", minimum: 24
    # Nothing painted: the guard blocks the post the server would refuse
    # anyway, and says so where the live count already is.
    click_button "Send me my organizer link"
    assert_text "Paint at least one time before sending"
    assert_current_path new_event_path

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
    assert_selector "input[type=submit][value='Send invitations']"
    assert_selector "dl.event-facts dd", text: "1 h 30 min"
    assert_selector "dl.event-facts a.quiet-link[href='https://zoom.us/j/1']", text: "zoom.us"
    event = Event.find_by(name: "Board games night")

    fill_in "Invite more people (one address per line or comma-separated)", with: "bob@example.com"
    click_button "Send invitations"
    assert_text "1 added. 1 invitation sent."
    assert_equal 1, event.guests.count
    assert_equal [ "Ege's place, Kadıköy", "https://zoom.us/j/1", 90 ], [ event.place, event.place_url, event.duration_minutes ]

    click_link "Edit details"
    assert_text "30-minute slots · #{event.time_zone}"
    fill_in "Place", with: "Zoom"
    click_button "Save details"
    assert_text "Details saved."
    assert_selector "dl.event-facts dd", text: /Zoom/
  end
end
