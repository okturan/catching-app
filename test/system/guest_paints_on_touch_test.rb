require "mobile_system_test_case"

class GuestPaintsOnTouchTest < MobileSystemTestCase
  test "guest scrolls by default and paints in paint mode" do
    event = events(:planning)
    event.update!(place: "Ege's place, Kadıköy, a very long unbroken description of where we meet that runs past the card width",
      place_url: "https://maps.example/place/some/very/long/path/that/does/not/wrap", duration_minutes: 120)
    event.activities.create!(name: "Averyveryverylongplanitemnamewithoutanyspacesatalltostretchthecardpastitswidth", duration: 45, position: 1,
      description: "A second line that is also rather long and should wrap inside the card instead of widening the page")

    visit participation_path(raw_token(:planning_guest))
    assert page.evaluate_script("matchMedia('(any-pointer: coarse)').matches"), "touch emulation is not active"
    assert_selector "#time-grid-show .slot.selectable", count: 2
    assert_selector "dl.event-facts a.quiet-link", text: "maps.example"
    assert_selector "dl.event-facts ol.event-plan li", count: 2
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "body scrolls horizontally"

    cells = all("#time-grid-show .slot.selectable")
    assert_selector "#time-grid-show .slot.active", count: 1

    touch_drag(cells.first, cells.last)
    assert_selector "#time-grid-show .slot.active", count: 1, wait: 1

    find("#paint-mode label", text: "Paint").click
    assert_selector "#paint-mode[data-mode='paint']"
    touch_drag(cells.last, cells.first)
    assert_selector "#time-grid-show .slot.active", count: 2
    assert_selector "button[form='availability-form']", visible: true

    click_button "Save"
    assert_text "Availability saved."
    assert_selector "#time-grid-show .slot.active", count: 2
  end
end
