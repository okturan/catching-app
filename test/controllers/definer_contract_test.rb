require "test_helper"

# The definer is a Stimulus controller on the form that finds its parts by
# target. Both pages that render it (planning a new event, changing the
# times of an existing one) share the partials, so a rename on one page
# cannot silently break the other.
class DefinerContractTest < ActionDispatch::IntegrationTest
  TARGETS = %w[grid slots zone step begin end rangeNote summary].freeze

  test "events/new keeps the definer contract" do
    get new_event_path

    assert_response :success
    assert_definer_contract
    assert_select "form select#event_slot_minutes option[selected][value='30']"
    assert_select "[data-definer-offer-value]", count: 0
    assert_select "[data-definer-picked-counts-value]", count: 0
    assert_select "form[data-controller='definer duration'][data-duration-step-value='30']" do
      assert_select "select#event_duration_minutes[data-duration-target=select]"
      assert_select "#duration-note[data-duration-target=note]"
    end
    assert_select "#event-begin[min]", count: 0
    assert_select "#grid-frozen-note", count: 0
  end

  test "offer/edit keeps the definer contract" do
    get edit_participant_offer_path(raw_token(:planning_organizer))

    assert_response :success
    assert_definer_contract
    assert_select "form#offer-form #time_slot_array"
    assert_select "form#offer-form[data-definer-offer-value]"
    assert_select "form#offer-form[data-definer-picked-counts-value]"
    assert_select "#event-begin[min]"
  end

  private

  def assert_definer_contract
    assert_select "form[data-controller~=definer][data-action~='definer#submit']" do
      TARGETS.each { |target| assert_select "[data-definer-target=#{target}]", { count: 1 }, "the #{target} target is missing or duplicated" }
    end
    assert_select "select#event_slot_minutes[data-action='definer#restep']"
    assert_select "select#timezone-picker-new[data-action='definer#rezone']"
    assert_select "input#event-begin[data-action='change->definer#redraw']"
    assert_select "input#event-end[data-action='change->definer#redraw']"
    assert_select "table#time-grid-define[role=grid][data-slot-minutes][data-time-zone][data-not-before]"
    assert_select "form select#event_slot_minutes[name='event[slot_minutes]']"
    assert_select "form select#timezone-picker-new[name='event[time_zone]'][data-selected]"
    assert_select "form input#time_slot_array[name='time_slots[time_slot_array]'][type=hidden]"
    assert_select "form input#event-begin[type=date]:not([name])"
    assert_select "form input#event-end[type=date]:not([name])"
    assert_select "form #range-tooltip[role=status]"
    assert_select "#selection-summary[aria-live=polite]"
    assert_select ".time-grid-panel[data-controller=paint-mode]" do
      assert_select "table#time-grid-define[data-paint-mode-target=grid]"
      assert_select "fieldset#paint-mode[role=radiogroup][data-paint-mode-target=switch] input[type=radio][name=paint-mode][data-action='paint-mode#choose']", count: 2
    end
    assert_select "form form", count: 0
  end
end
