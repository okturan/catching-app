require "test_helper"

module Participations
  # Covers ActivitiesController and ActivityMovesController: the two plan
  # writers behind the organizer's Edit details page.
  class ActivitiesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @event = events(:planning)
      @organizer = participants(:planning_organizer)
      @item = activities(:planning_activity)
      @organizer_token = raw_token(:planning_organizer)
      @guest_token = raw_token(:planning_guest)
    end

    def plan_names
      @event.activities.reload.pluck(:name)
    end

    test "the organizer adds an item through the token family; it goes to the end and bumps the revision" do
      assert_difference "@event.activities.count", 1 do
        post participation_activities_path(@organizer_token), params: { activity: { name: " Pizza  first ", duration: "30", description: "  " } }
      end

      assert_response :see_other
      assert_redirected_to edit_participation_details_path(@organizer_token)
      assert_equal "Plan updated.", flash[:notice]
      item = @event.activities.reload.last
      assert_equal [ "Pizza first", 30, nil, 1 ], [ item.name, item.duration, item.description, item.position ]
      assert_equal [ "Board games", "Pizza first" ], plan_names
      assert_equal 1, @event.reload.revision
    end

    test "the organizer edits, moves and removes through the session family" do
      sign_in users(:owner)
      dune = @event.activities.create!(name: "Dune", duration: 155, position: 1)

      patch my_participation_activity_path(@organizer, @item), params: { activity: { name: "Board games", duration: "45", description: "Bring Pandemic" } }
      assert_response :see_other
      assert_redirected_to edit_my_participation_details_path(@organizer)
      assert_equal "Plan updated.", flash[:notice]
      @item.reload
      assert_equal [ 45, "Bring Pandemic" ], [ @item.duration, @item.description ]

      post my_participation_activity_move_path(@organizer, dune), params: { move: { position: 0 } }
      assert_redirected_to edit_my_participation_details_path(@organizer)
      assert_equal [ "Dune", "Board games" ], plan_names
      assert_equal [ 0, 1 ], @event.activities.reload.pluck(:position)

      delete my_participation_activity_path(@organizer, dune)
      assert_redirected_to edit_my_participation_details_path(@organizer)
      assert_equal "Plan updated.", flash[:notice]
      assert_equal [ "Board games" ], plan_names
      assert_equal 3, @event.reload.revision
    end

    test "a guest is not found on every plan write and the plan is unchanged" do
      before = @event.activities.pluck(:id, :name, :position)

      post participation_activities_path(@guest_token), params: { activity: { name: "Hijack" } }
      assert_response :not_found
      assert_select "#link-not-found"
      patch participation_activity_path(@guest_token, @item), params: { activity: { name: "Hijack" } }
      assert_response :not_found
      delete participation_activity_path(@guest_token, @item)
      assert_response :not_found
      post participation_activity_move_path(@guest_token, @item), params: { move: { position: 0 } }
      assert_response :not_found

      sign_in users(:invitee)
      guest = participants(:planning_guest)
      post my_participation_activities_path(guest), params: { activity: { name: "Hijack" } }
      assert_response :not_found
      patch my_participation_activity_path(guest, @item), params: { activity: { name: "Hijack" } }
      assert_response :not_found
      delete my_participation_activity_path(guest, @item)
      assert_response :not_found
      post my_participation_activity_move_path(guest, @item), params: { move: { position: 0 } }
      assert_response :not_found

      assert_equal before, @event.activities.reload.pluck(:id, :name, :position)
      assert_equal 0, @event.reload.revision
    end

    test "another event's item is unreachable through the organizer's link" do
      other = events(:other_event).activities.create!(name: "Elsewhere")

      patch participation_activity_path(@organizer_token, other), params: { activity: { name: "Taken" } }
      assert_response :not_found
      delete participation_activity_path(@organizer_token, other)
      assert_response :not_found
      post participation_activity_move_path(@organizer_token, other), params: { move: { position: 0 } }
      assert_response :not_found

      assert_equal "Elsewhere", other.reload.name
      assert_equal 0, @event.reload.revision
    end

    test "a finalized event still takes plan writes; a cancelled one refuses them with one alert" do
      token = raw_token(:finalized_organizer)
      post participation_activities_path(token), params: { activity: { name: "Pizza", duration: "30" } }
      assert_redirected_to edit_participation_details_path(token)
      assert_equal [ "Pizza" ], events(:finalized).activities.pluck(:name)
      assert_equal 1, events(:finalized).reload.revision

      @event.update_columns(cancelled_at: Time.current)
      post participation_activities_path(@organizer_token), params: { activity: { name: "Late" } }
      assert_response :see_other
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      patch participation_activity_path(@organizer_token, @item), params: { activity: { name: "Late" } }
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      delete participation_activity_path(@organizer_token, @item)
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      post participation_activity_move_path(@organizer_token, @item), params: { move: { position: 0 } }
      assert_redirected_to participation_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]

      assert_equal [ "Board games" ], plan_names
      assert_equal 0, @event.reload.revision
    end

    test "a refused item sends the organizer back with the errors and writes nothing" do
      post participation_activities_path(@organizer_token), params: { activity: { name: "", duration: "0" } }
      assert_response :see_other
      assert_redirected_to edit_participation_details_path(@organizer_token)
      assert_equal "Name can't be blank and Duration must be greater than 0", flash[:alert]
      assert_equal [ "Board games" ], plan_names
      assert_equal 0, @event.reload.revision

      patch participation_activity_path(@organizer_token, @item), params: { activity: { name: "x" * 81 } }
      assert_equal "Name is too long (maximum is 80 characters)", flash[:alert]
      assert_equal "Board games", @item.reload.name

      19.times { |index| @event.activities.create!(name: "Item #{index}", position: index + 1) }
      post participation_activities_path(@organizer_token), params: { activity: { name: "Twenty-one" } }
      assert_equal "The plan can have at most 20 items", flash[:alert]
      assert_equal 20, @event.activities.count
      assert_equal 0, @event.reload.revision
    end

    test "moves renumber densely, clamp the target and bump the revision only when the order changes" do
      dune, credits = %w[Dune Credits].map { |name| @event.activities.create!(name: name, position: 0) }
      assert_equal [ @item.id, dune.id, credits.id ], @event.activities.reload.pluck(:id), "ties order by id"

      post participation_activity_move_path(@organizer_token, @item), params: { move: { position: 1 } }
      assert_response :see_other
      assert_redirected_to edit_participation_details_path(@organizer_token)
      assert_equal "Plan updated.", flash[:notice]
      assert_equal [ dune.id, @item.id, credits.id ], @event.activities.reload.pluck(:id)
      assert_equal [ 0, 1, 2 ], @event.activities.pluck(:position)
      assert_equal 1, @event.reload.revision

      post participation_activity_move_path(@organizer_token, dune), params: { move: { position: 99 } }
      assert_equal [ @item.id, credits.id, dune.id ], @event.activities.reload.pluck(:id)
      assert_equal [ 0, 1, 2 ], @event.activities.pluck(:position)
      assert_equal 2, @event.reload.revision

      post participation_activity_move_path(@organizer_token, @item), params: { move: { position: -1 } }
      assert_equal "Plan updated.", flash[:notice]
      assert_equal [ @item.id, credits.id, dune.id ], @event.activities.reload.pluck(:id)
      assert_equal 2, @event.reload.revision

      post participation_activity_move_path(@organizer_token, @item), params: { move: { position: "top" } }
      assert_redirected_to edit_participation_details_path(@organizer_token)
      assert_equal "Pick a position for the item", flash[:alert]
      assert_equal 2, @event.reload.revision
    end

    test "plan writes enqueue no mail and create no ledger row" do
      assert_no_enqueued_jobs do
        assert_no_difference "MailDelivery.count" do
          post participation_activities_path(@organizer_token), params: { activity: { name: "Pizza" } }
          delete participation_activity_path(@organizer_token, @event.activities.reload.last)
        end
      end

      assert_equal 2, @event.reload.revision
      assert_equal [ "Board games" ], plan_names
    end

    test "plan writes need a session in the account family and are not cached" do
      post my_participation_activities_path(@organizer), params: { activity: { name: "Pizza" } }
      assert_redirected_to new_user_session_path
      assert_equal [ "Board games" ], plan_names

      post participation_activities_path(@organizer_token), params: { activity: { name: "Pizza" } }
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end
end
