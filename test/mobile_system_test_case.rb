require "test_helper"

# A second Capybara driver emulating a touch phone. The distinct driver name
# gives it its own browser session next to ApplicationSystemTestCase.
class MobileSystemTestCase < ActionDispatch::SystemTestCase
  include SystemTestHelper

  ANDROID_USER_AGENT = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36".freeze

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 915 ], options: { name: :mobile_chrome } do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_emulation(
      device_metrics: { width: 412, height: 915, pixelRatio: 2.625, touch: true },
      user_agent: ANDROID_USER_AGENT
    )
  end

  private

  # innerWidth grows with the overflow on a phone, so the page is measured
  # against the width the phone shows.
  def assert_no_sideways_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "the page scrolls sideways"
  end

  # Drags one finger from the first element through the others using real
  # touch events dispatched through DevTools (chromedriver's synthetic touch
  # pointer does not reach the page under mobile emulation). The grid panel is
  # scrolled fully into view first so the sticky action bar covers no cell.
  def touch_drag(from, *through)
    browser = page.driver.browser
    page.execute_script("arguments[0].closest('.time-grid-panel').scrollIntoView({ block: 'end', behavior: 'instant' })", from)
    settle_layout
    points = [ from, *through ].map { |element| center_of(element) }
    x, y = points.first
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: x, y: y } ])
    points.each_cons(2) do |(x1, y1), (x2, y2)|
      steps = 6
      (1..steps).each do |step|
        fraction = step / steps.to_f
        browser.execute_cdp("Input.dispatchTouchEvent", type: "touchMove",
          touchPoints: [ { x: x1 + (x2 - x1) * fraction, y: y1 + (y2 - y1) * fraction } ])
      end
    end
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
  end

  # Waits two animation frames so scrolling and sticky positioning are laid out.
  def settle_layout
    page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
  end

  def center_of(element)
    page.evaluate_script(
      "(function (e) { const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })(arguments[0])",
      element
    )
  end
end
