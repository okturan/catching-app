require "application_system_test_case"

class OrganizerPaintsWithMouseTest < ApplicationSystemTestCase
  setup do
    login_as users(:owner), scope: :user
  end

  test "organizer paints two adjacent cells and the selection follows the zone" do
    visit new_event_path
    assert_selector "#time-grid-define .slot[data-date]", minimum: 24

    first_cell = find('#time-grid-define .slot[data-row="9"][data-col="0"]')
    second_cell = find('#time-grid-define .slot[data-row="10"][data-col="0"]')
    page.driver.browser.action.move_to(first_cell.native).pointer_down.move_to(second_cell.native).pointer_up.perform

    assert_selector "#time-grid-define .slot.active", count: 2
    assert_text "2 slots on 1 day"

    times = hidden_value("#time_slot_array").split(",").map { |value| Time.iso8601(value) }.sort
    assert_equal 2, times.size
    assert_equal 1800, times.last - times.first, "the form defaults to 30-minute slots"

    previous_zone = find("#timezone-picker-new").value
    select "Asia/Tokyo", from: "timezone-picker-new"

    expected = times.map do |time|
      local = time.in_time_zone(previous_zone)
      ActiveSupport::TimeZone["Asia/Tokyo"].local(local.year, local.month, local.day, local.hour, local.min).utc.iso8601(3)
    end
    assert_equal expected.sort, hidden_value("#time_slot_array").split(",").sort
    assert_selector "#time-grid-define .slot.active", count: 2
    assert_text "Moved to Asia/Tokyo wall clock"
  end

  test "the grid is one tab stop and Space toggles a cell" do
    visit new_event_path
    assert_selector "#time-grid-define .slot[data-date]", minimum: 24

    cell = find('#time-grid-define .slot[tabindex="0"]')
    cell.send_keys(:space)
    assert_selector "#time-grid-define .slot.active", count: 1
    assert_equal "true", cell["aria-selected"]

    cell.send_keys(:tab)
    assert_equal false, page.evaluate_script("document.activeElement.classList.contains('slot')")
  end
end
