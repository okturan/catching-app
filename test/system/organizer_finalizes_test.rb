require "application_system_test_case"

class OrganizerFinalizesTest < ApplicationSystemTestCase
  setup do
    @event = events(:planning)
    hours = [ 10, 11, 12 ].map { |hour| Time.utc(2030, 1, 15, hour) }
    @event.replace_time_slots!(participant: participants(:planning_organizer), starts_at: hours)
    @event.replace_time_slots!(participant: participants(:planning_guest), starts_at: [ hours[0], hours[2] ])
  end

  test "the organizer picks consensus cells and sets the time in stone" do
    visit participation_path(raw_token(:planning_organizer))

    assert_selector "#time-grid-show[data-role=organizer] .slot.selectable", count: 2
    assert_selector "#time-grid-show .slot.consensus", count: 2

    find('#time-grid-show .slot.selectable[data-date="2030-01-15T10:00:00.000Z"]').click
    find('#time-grid-show .slot.selectable[data-date="2030-01-15T12:00:00.000Z"]').click
    assert_text "Not one continuous window"

    find('#time-grid-show .slot.selectable[data-date="2030-01-15T12:00:00.000Z"]').click
    assert_text "(1 h)"

    click_button "Set in stone"
    assert_text "Meeting time confirmed."
    assert_selector "#time-grid-show[data-finalized]"
    @event.reload
    assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
    assert_equal Time.utc(2030, 1, 15, 11), @event.end_time
  end
end
