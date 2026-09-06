require "application_system_test_case"

class GuestReadsZonedTimesTest < ApplicationSystemTestCase
  setup do
    @event = events(:finalized)
    @event.activities.create!(name: "Pizza first", duration: 30, position: 0)
    @event.activities.create!(name: "The movie", duration: 120, position: 1)
    participants(:finalized_guest).update!(time_zone: "Europe/Berlin")
  end

  test "derived plan starts follow the picker zone on load and on change" do
    visit participation_path(raw_token(:finalized_guest))

    assert_equal "Europe/Berlin", find("#timezone-picker-show").value
    assert_equal [ "11:00 (Europe/Berlin)", "11:30 (Europe/Berlin)" ], plan_starts
    assert_selector "#final-window-local", text: "Tue 15 Jan 11:00–12:00 (Europe/Berlin)"

    select "Asia/Tokyo", from: "timezone-picker-show"
    assert_equal [ "19:00 (Asia/Tokyo)", "19:30 (Asia/Tokyo)" ], plan_starts
    assert_selector "#final-window-local", text: "Tue 15 Jan 19:00–20:00 (Asia/Tokyo)"

    select "UTC", from: "timezone-picker-show"
    assert_equal [ "10:00 (UTC)", "10:30 (UTC)" ], plan_starts
  end

  test "dated notes on a cancelled page keep their date in the picker zone" do
    @event.cancel!

    visit participation_path(raw_token(:finalized_guest))

    assert_selector ".event-when.is-cancelled", text: "Was set for Tue 15 Jan 2030 11:00 (Europe/Berlin) to 12:00 (Europe/Berlin)"
    assert_selector ".event-when.is-cancelled time[data-zoned-format='date-time']", text: /\(Europe\/Berlin\)\z/

    select "Asia/Tokyo", from: "timezone-picker-show"
    assert_selector ".event-when.is-cancelled", text: "Was set for Tue 15 Jan 2030 19:00 (Asia/Tokyo) to 20:00 (Asia/Tokyo)"
    assert_no_selector ".event-when.is-cancelled time", text: /Europe\/Berlin/
  end

  private

  def plan_starts
    all("dl.event-facts ol.event-plan li time[data-zoned-instant]").map(&:text)
  end
end
