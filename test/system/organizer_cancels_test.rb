require "application_system_test_case"

class OrganizerCancelsTest < ApplicationSystemTestCase
  test "the organizer calls it off and every page turns read-only" do
    visit participation_path(raw_token(:planning_organizer))
    assert_selector "#time-grid-show[data-role=organizer]"

    accept_confirm "Cancel Planning session for everyone? Everyone with a link gets one last email. This cannot be undone." do
      click_button "Cancel this event"
    end

    assert_text "Event cancelled. 3 people were told."
    assert_selector "h1 .plate.plate-ink", text: /cancelled/i
    assert_selector "#time-grid-show[data-role=viewer][data-cancelled]"
    assert_no_selector "#time-grid-show .slot.selectable"
    assert_text "Cancelled on"
    assert_no_button "Set in stone"
    assert_no_button "Cancel this event"
    assert_no_link "Edit details"
    assert_link "Plan a new event"
    assert events(:planning).reload.cancelled?

    visit participation_path(raw_token(:planning_guest))
    assert_selector "h1 .plate.plate-ink", text: /cancelled/i
    assert_selector "#time-grid-show[data-role=viewer][data-cancelled]"
    assert_no_selector "#availability-form"
    assert_no_button "Save"
    assert_no_button "None of these times work"
    assert_button "Leave this event"
  end
end
