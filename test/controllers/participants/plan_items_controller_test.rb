require "test_helper"

module Participants
  # Covers PlanItemsController and PlanItemMovesController: the two plan
  # writers behind the organizer's Edit details page.
  class PlanItemsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:planning)
      @organizer = participants(:planning_organizer)
      @item = plan_items(:planning_plan_item)
      @organizer_token = raw_token(:planning_organizer)
      @guest_token = raw_token(:planning_guest)
    end

    def plan_names
      @event.plan_items.reload.pluck(:name)
    end

    test "the organizer adds an item through a link; it goes to the end and bumps the revision" do
      assert_difference "@event.plan_items.count", 1 do
        post participant_plan_items_path(@organizer_token), params: { plan_item: { name: " Pizza  first ", duration_minutes: "30", description: "  " } }
      end

      assert_response :see_other
      assert_redirected_to edit_participant_details_path(@organizer_token)
      assert_equal "Plan updated.", flash[:notice]
      item = @event.plan_items.reload.last
      assert_equal [ "Pizza first", 30, nil, 1 ], [ item.name, item.duration_minutes, item.description, item.position ]
      assert_equal [ "Board games", "Pizza first" ], plan_names
      assert_equal 1, @event.reload.revision
    end

    test "the organizer edits, moves and removes through the account" do
      sign_in users(:owner)
      dune = @event.plan_items.create!(name: "Dune", duration_minutes: 155, position: 1)

      patch participant_plan_item_path(@organizer, @item), params: { plan_item: { name: "Board games", duration_minutes: "45", description: "Bring Pandemic" } }
      assert_response :see_other
      assert_redirected_to edit_participant_details_path(@organizer)
      assert_equal "Plan updated.", flash[:notice]
      @item.reload
      assert_equal [ 45, "Bring Pandemic" ], [ @item.duration_minutes, @item.description ]

      post participant_plan_item_move_path(@organizer, dune), params: { move: { position: 0 } }
      assert_redirected_to edit_participant_details_path(@organizer)
      assert_equal [ "Dune", "Board games" ], plan_names
      assert_equal [ 0, 1 ], @event.plan_items.reload.pluck(:position)

      delete participant_plan_item_path(@organizer, dune)
      assert_redirected_to edit_participant_details_path(@organizer)
      assert_equal "Plan updated.", flash[:notice]
      assert_equal [ "Board games" ], plan_names
      assert_equal 3, @event.reload.revision
    end

    test "a guest is not found on every plan write and the plan is unchanged" do
      before = @event.plan_items.pluck(:id, :name, :position)

      post participant_plan_items_path(@guest_token), params: { plan_item: { name: "Hijack" } }
      assert_response :not_found
      assert_select "#link-not-found"
      patch participant_plan_item_path(@guest_token, @item), params: { plan_item: { name: "Hijack" } }
      assert_response :not_found
      delete participant_plan_item_path(@guest_token, @item)
      assert_response :not_found
      post participant_plan_item_move_path(@guest_token, @item), params: { move: { position: 0 } }
      assert_response :not_found

      sign_in users(:invitee)
      guest = participants(:planning_guest)
      post participant_plan_items_path(guest), params: { plan_item: { name: "Hijack" } }
      assert_response :not_found
      patch participant_plan_item_path(guest, @item), params: { plan_item: { name: "Hijack" } }
      assert_response :not_found
      delete participant_plan_item_path(guest, @item)
      assert_response :not_found
      post participant_plan_item_move_path(guest, @item), params: { move: { position: 0 } }
      assert_response :not_found

      assert_equal before, @event.plan_items.reload.pluck(:id, :name, :position)
      assert_equal 0, @event.reload.revision
    end

    test "another event's item is unreachable through the organizer's link" do
      other = events(:other_event).plan_items.create!(name: "Elsewhere")

      patch participant_plan_item_path(@organizer_token, other), params: { plan_item: { name: "Taken" } }
      assert_response :not_found
      delete participant_plan_item_path(@organizer_token, other)
      assert_response :not_found
      post participant_plan_item_move_path(@organizer_token, other), params: { move: { position: 0 } }
      assert_response :not_found

      assert_equal "Elsewhere", other.reload.name
      assert_equal 0, @event.reload.revision
    end

    test "a finalized event still takes plan writes; a cancelled one refuses them with one alert" do
      token = raw_token(:finalized_organizer)
      post participant_plan_items_path(token), params: { plan_item: { name: "Pizza", duration_minutes: "30" } }
      assert_redirected_to edit_participant_details_path(token)
      assert_equal [ "Pizza" ], events(:finalized).plan_items.pluck(:name)
      assert_equal 1, events(:finalized).reload.revision

      @event.update_columns(cancelled_at: Time.current)
      post participant_plan_items_path(@organizer_token), params: { plan_item: { name: "Late" } }
      assert_response :see_other
      assert_redirected_to participant_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      patch participant_plan_item_path(@organizer_token, @item), params: { plan_item: { name: "Late" } }
      assert_redirected_to participant_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      delete participant_plan_item_path(@organizer_token, @item)
      assert_redirected_to participant_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]
      post participant_plan_item_move_path(@organizer_token, @item), params: { move: { position: 0 } }
      assert_redirected_to participant_path(@organizer_token)
      assert_equal "This event was cancelled", flash[:alert]

      assert_equal [ "Board games" ], plan_names
      assert_equal 0, @event.reload.revision
    end

    test "a refused item sends the organizer back with the errors and writes nothing" do
      post participant_plan_items_path(@organizer_token), params: { plan_item: { name: "", duration_minutes: "0" } }
      assert_response :see_other
      assert_redirected_to edit_participant_details_path(@organizer_token)
      assert_equal "Name can't be blank and Length must be greater than 0", flash[:alert]
      assert_equal [ "Board games" ], plan_names
      assert_equal 0, @event.reload.revision

      patch participant_plan_item_path(@organizer_token, @item), params: { plan_item: { name: "x" * 81 } }
      assert_equal "Name is too long (maximum is 80 characters)", flash[:alert]
      assert_equal "Board games", @item.reload.name

      19.times { |index| @event.plan_items.create!(name: "Item #{index}", position: index + 1) }
      post participant_plan_items_path(@organizer_token), params: { plan_item: { name: "Twenty-one" } }
      assert_equal "The plan can have at most 20 items", flash[:alert]
      assert_equal 20, @event.plan_items.count
      assert_equal 0, @event.reload.revision
    end

    test "moves renumber densely, clamp the target and bump the revision only when the order changes" do
      dune, credits = %w[Dune Credits].map { |name| @event.plan_items.create!(name: name, position: 0) }
      assert_equal [ @item.id, dune.id, credits.id ], @event.plan_items.reload.pluck(:id), "ties order by id"

      post participant_plan_item_move_path(@organizer_token, @item), params: { move: { position: 1 } }
      assert_response :see_other
      assert_redirected_to edit_participant_details_path(@organizer_token)
      assert_equal "Plan updated.", flash[:notice]
      assert_equal [ dune.id, @item.id, credits.id ], @event.plan_items.reload.pluck(:id)
      assert_equal [ 0, 1, 2 ], @event.plan_items.pluck(:position)
      assert_equal 1, @event.reload.revision

      post participant_plan_item_move_path(@organizer_token, dune), params: { move: { position: 99 } }
      assert_equal [ @item.id, credits.id, dune.id ], @event.plan_items.reload.pluck(:id)
      assert_equal [ 0, 1, 2 ], @event.plan_items.pluck(:position)
      assert_equal 2, @event.reload.revision

      post participant_plan_item_move_path(@organizer_token, @item), params: { move: { position: -1 } }
      assert_equal "Plan updated.", flash[:notice]
      assert_equal [ @item.id, credits.id, dune.id ], @event.plan_items.reload.pluck(:id)
      assert_equal 2, @event.reload.revision

      post participant_plan_item_move_path(@organizer_token, @item), params: { move: { position: "top" } }
      assert_redirected_to edit_participant_details_path(@organizer_token)
      assert_equal "Pick a position for the item", flash[:alert]
      assert_equal 2, @event.reload.revision
    end

    test "plan writes enqueue no mail and create no ledger row" do
      assert_no_enqueued_jobs do
        assert_no_difference "MailDelivery.count" do
          post participant_plan_items_path(@organizer_token), params: { plan_item: { name: "Pizza" } }
          delete participant_plan_item_path(@organizer_token, @event.plan_items.reload.last)
        end
      end

      assert_equal 2, @event.reload.revision
      assert_equal [ "Board games" ], plan_names
    end

    test "plan writes by id need the account and are not cached" do
      post participant_plan_items_path(@organizer), params: { plan_item: { name: "Pizza" } }
      assert_redirected_to new_session_path
      assert_equal [ "Board games" ], plan_names

      post participant_plan_items_path(@organizer_token), params: { plan_item: { name: "Pizza" } }
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end
end
