require "test_helper"

module Participations
  class ParticipantsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:planning)
      @organizer_token = raw_token(:planning_organizer)
      @guest = participants(:planning_guest)
    end

    test "removing a guest deletes the row and slots but keeps the ledger" do
      row = MailDelivery.create!(event: @event, participant: @guest, kind: :invitation, recipient_email: @guest.email, sender_email: "owner@example.com")

      delete participation_participant_path(@organizer_token, @guest)

      assert_redirected_to participation_path(@organizer_token)
      assert_not Participant.exists?(@guest.id)
      assert_equal 0, TimeSlot.where(participant_id: @guest.id).count
      assert_nil row.reload.participant_id
      assert_not_includes @event.mutually_available_start_times, Time.utc(2030, 1, 15, 10)
    end

    test "the organizer, foreign guests and guest tokens are not found" do
      delete participation_participant_path(@organizer_token, participants(:planning_organizer))
      assert_response :not_found
      delete participation_participant_path(@organizer_token, participants(:finalized_guest))
      assert_response :not_found
      delete participation_participant_path(raw_token(:planning_guest), participants(:planning_pending))
      assert_response :not_found
      assert Participant.exists?(participants(:planning_pending).id)
    end
  end
end
