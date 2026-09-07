require "application_system_test_case"

class OrganizerEditsPlanTest < ApplicationSystemTestCase
  test "the organizer builds and reorders the plan and a guest reads it in order" do
    events(:planning).activities.delete_all

    visit participation_path(raw_token(:planning_organizer))
    click_link "Edit details"
    assert_text "Nothing planned yet"

    within "#plan-add-form" do
      fill_in "Add to the plan", with: "Pizza first"
      select "30 min", from: "Length"
      click_button "Add to the plan"
    end
    assert_selector ".plan-item .plan-item-head", text: "1. Pizza first · 30 min"

    within "#plan-add-form" do
      fill_in "Add to the plan", with: "The movie"
      select "2 h", from: "Length"
      fill_in "Description", with: "Dune, part one"
      click_button "Add to the plan"
    end
    assert_selector ".plan-item", count: 2
    assert_selector ".plan-item:nth-child(2) .plan-item-head", text: "2. The movie · 2 h"

    find("button[aria-label='Move The movie up']").click
    assert_selector ".plan-item:nth-child(1) .plan-item-head", text: "1. The movie · 2 h"
    assert_selector ".plan-item:nth-child(2) .plan-item-head", text: "2. Pizza first · 30 min"

    within ".plan-item:nth-child(2) form.plan-item-form" do
      find("input[name='activity[name]']").set("Pizza and salad")
      click_button "Save"
    end
    assert_selector ".plan-item:nth-child(2) .plan-item-head", text: "2. Pizza and salad · 30 min"

    within "#plan-add-form" do
      fill_in "Add to the plan", with: "Credits"
      click_button "Add to the plan"
    end
    assert_selector ".plan-item", count: 3
    accept_confirm "Remove Credits from the plan?" do
      find("button[aria-label='Remove Credits']").click
    end
    assert_selector ".plan-item", count: 2
    assert_text "Plan updated."

    visit participation_path(raw_token(:planning_guest))
    assert_equal [ "The movie · 2 h", "Pizza and salad · 30 min" ], all("dl.event-facts ol.event-plan li .event-plan-item").map(&:text)
    assert_selector "dl.event-facts .event-plan-note", text: "Dune, part one"
    assert_no_selector "dl.event-facts time[data-zoned-instant]"
  end
end
