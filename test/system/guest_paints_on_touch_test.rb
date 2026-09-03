require "mobile_system_test_case"

class GuestPaintsOnTouchTest < MobileSystemTestCase
  setup do
    login_as users(:invitee), scope: :user
  end

  test "guest scrolls by default and paints in paint mode" do
    visit event_path(events(:planning))
    assert page.evaluate_script("matchMedia('(any-pointer: coarse)').matches"), "touch emulation is not active"
    assert_selector "#time-grid-show .slot.selectable", count: 2
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

    click_button "Confirm"
    assert_text "Availability saved."
    assert_selector "#time-grid-show .slot.active", count: 2
  end
end
