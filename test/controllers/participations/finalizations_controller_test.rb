require "test_helper"

module Participations
  class FinalizationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:planning)
      @organizer_token = raw_token(:planning_organizer)
      @consensus = "2030-01-15T10:00:00Z"
    end

    test "organizer finalizes a mutually available slot and everyone linked is notified" do
      assert_difference "MailDelivery.finalized.count", 3 do
        post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: @consensus } }
      end

      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Meeting time confirmed.", flash[:notice]
      @event.reload
      assert @event.status?
      assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
      assert_equal Time.utc(2030, 1, 15, 11), @event.end_time
    end

    test "a guest token cannot finalize" do
      post participation_finalization_path(raw_token(:planning_guest)), params: { time_slots: { time_slot_array: @consensus } }

      assert_response :not_found
      assert_not @event.reload.status?
    end

    test "finalization errors redirect with the exact message" do
      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
      assert_response :see_other
      assert_equal "Select only time slots available to every participant", flash[:alert]

      later = Time.utc(2030, 1, 15, 12)
      @event.replace_time_slots!(participant: participants(:planning_organizer), starts_at: [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11), later ])
      @event.replace_time_slots!(participant: participants(:planning_guest), starts_at: [ Time.utc(2030, 1, 15, 10), later ])
      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: [ @consensus, later.iso8601 ].join(",") } }
      assert_response :see_other
      assert_equal "Select one continuous meeting window", flash[:alert]

      post participation_finalization_path(raw_token(:finalized_organizer)), params: { time_slots: { time_slot_array: @consensus } }
      assert_response :see_other
      assert_equal "Availability is closed for this event", flash[:alert]
    end

    test "an event nobody replied to cannot be finalized" do
      participants(:planning_guest).update!(declined_at: Time.current)

      post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: @consensus } }

      assert_response :see_other
      assert_equal "Wait for at least one reply before confirming", flash[:alert]
    end
  end
end
