require "application_system_test_case"

class OrganizerRevisesOfferTest < ApplicationSystemTestCase
  TEN = "2030-01-15T10:00:00.000Z"
  ELEVEN = "2030-01-15T11:00:00.000Z"
  TWELVE = "2030-01-15T12:00:00.000Z"

  test "the organizer removes a picked time, the voided guest is asked again and replies, and the table follows" do
    guest = participants(:planning_guest)

    visit participation_path(raw_token(:planning_organizer))
    click_link "Change the times"
    assert_text "Change the times"
    assert_selector "#time-grid-define .slot.active", count: 2
    assert_selector "#time-grid-define .slot[data-date='#{TEN}'] .others", text: "+1"
    assert_selector "#time-grid-define .slot[data-date='#{TEN}'][aria-label$=', 1 guest picked this']"
    assert_equal "#{TEN},#{ELEVEN}", hidden_value("#time_slot_array")
    assert_selector "select#event_slot_minutes:disabled"
    assert_text "Fixed since the first reply"
    assert_no_selector "#offer-form[data-turbo-confirm]"

    find("#time-grid-define .slot.selectable[data-date='#{TEN}']").click
    assert_text "Removing 1 time with 1 guest pick"
    assert_selector "#offer-form[data-turbo-confirm='Remove 1 time with 1 guest pick?']"

    find("#time-grid-define .slot.selectable[data-date='#{TEN}']").click
    assert_no_text "Removing"
    assert_no_selector "#offer-form[data-turbo-confirm]"

    find("#time-grid-define .slot.selectable[data-date='#{TEN}']").click
    find("#time-grid-define .slot.selectable[data-date='#{TWELVE}']").click
    assert_text "2 slots on 1 day. Removing 1 time with 1 guest pick"
    accept_confirm "Remove 1 time with 1 guest pick?" do
      click_button "Save the new times"
    end

    assert_text "Times updated: 1 added, 1 removed. 1 guest emailed. 1 guest needs a new reply."
    assert_selector "#participant-table td", text: "needs a new reply"
    assert_selector ".grid-action-bar .grid-notice", text: "1 guest has not answered the current times"
    assert_text "No one has answered the current times yet."
    assert_no_button "Set in stone"
    assert guest.reload.reply_voided_at.present?
    assert_equal 0, guest.time_slots.count

    visit participation_path(raw_token(:planning_guest))
    assert_selector ".grid-action-bar .grid-notice[role=status]", text: "None of the times you picked are offered any more. Pick again."
    assert_equal "[]", hidden_value("#my-time-slots")
    assert_selector "#time-grid-show .slot.selectable", count: 2
    assert_no_selector "#time-grid-show .slot.active"
    assert_selector "button[form='availability-form']", visible: true

    find("#time-grid-show .slot.selectable[data-date='#{ELEVEN}']").click
    assert_text "1 slot on 1 day"
    click_button "Save"
    assert_text "Availability saved."
    assert_no_selector ".grid-action-bar .grid-notice"
    assert_selector "#time-grid-show .slot.active", count: 1
    assert_nil guest.reload.reply_voided_at

    visit participation_path(raw_token(:planning_organizer))
    assert_selector "#participant-table td", text: "replied (1 slot)"
    assert_no_selector ".grid-action-bar .grid-notice"
    assert_button "Set in stone"
  end
end
