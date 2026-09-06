require "test_helper"

# The definer JavaScript finds its controls by id. Both pages that render it
# (planning a new event, changing the times of an existing one) share the
# partials, so a rename on one page cannot silently break the other.
class DefinerContractTest < ActionDispatch::IntegrationTest
  IDS = %w[time-grid-define timezone-picker-new event_slot_minutes time_slot_array event-begin event-end range-tooltip selection-summary paint-mode].freeze

  test "events/new keeps the definer contract" do
    get new_event_path

    assert_response :success
    assert_definer_contract
    assert_select "form select#event_slot_minutes option[selected][value='30']"
    assert_select "#current-offer", count: 0
    assert_select "#guest-picked-counts", count: 0
    assert_select "#event-begin[min]", count: 0
    assert_select "#grid-frozen-note", count: 0
  end

  test "offer/edit keeps the definer contract" do
    get edit_participation_offer_path(raw_token(:planning_organizer))

    assert_response :success
    assert_definer_contract
    assert_select "form#offer-form #time_slot_array"
    assert_select "form#offer-form #current-offer"
    assert_select "form#offer-form #guest-picked-counts"
    assert_select "#event-begin[min]"
  end

  private

  def assert_definer_contract
    IDS.each { |id| assert_select "##{id}", { count: 1 }, "##{id} is missing or duplicated" }
    assert_select "table#time-grid-define[role=grid][data-slot-minutes][data-time-zone][data-not-before]"
    assert_select "form select#event_slot_minutes[name='event[slot_minutes]']"
    assert_select "form select#timezone-picker-new[name='event[time_zone]'][data-selected]"
    assert_select "form input#time_slot_array[name='time_slots[time_slot_array]'][type=hidden]"
    assert_select "form input#event-begin[type=date]:not([name])"
    assert_select "form input#event-end[type=date]:not([name])"
    assert_select "form #range-tooltip[role=status]"
    assert_select "#selection-summary[aria-live=polite]"
    assert_select "fieldset#paint-mode[role=radiogroup] input[type=radio][name=paint-mode]", count: 2
    assert_select "form form", count: 0
  end
end
