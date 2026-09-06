require "mobile_system_test_case"

# The definer page at 412 px, which nothing had ever checked. Document order is
# task order here: the grid is the only genuinely required input on the page,
# so it has to come before the button that posts it, and the bar that carries
# the live count must not sit on top of that button.
class OrganizerPlansOnTouchTest < MobileSystemTestCase
  test "the planning page fits a phone, puts the grid before the submit and keeps the sticky bar off it" do
    visit new_event_path
    assert page.evaluate_script("matchMedia('(any-pointer: coarse)').matches"), "touch emulation is not active"
    assert_selector "#time-grid-define .slot[data-date]", minimum: 24
    settle_layout

    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"),
      "the page scrolls horizontally"

    assert_operator document_top("#time-grid-define"), :<, document_top("input[type=submit]"),
      "the submit comes before the grid it posts"

    page.execute_script("document.querySelector('input[type=submit]').scrollIntoView({ block: 'end', behavior: 'instant' })")
    settle_layout
    assert_operator viewport_bottom(".grid-action-bar"), :<=, viewport_top("input[type=submit]"),
      "the sticky action bar covers the submit"
  end

  private

  def document_top(selector)
    rect(selector, "top + window.scrollY")
  end

  def viewport_top(selector)
    rect(selector, "top")
  end

  def viewport_bottom(selector)
    rect(selector, "bottom")
  end

  def rect(selector, expression)
    page.evaluate_script(
      "(function () { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return r.#{expression}; })()"
    )
  end
end
