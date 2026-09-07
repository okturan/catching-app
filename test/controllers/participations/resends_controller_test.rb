require "test_helper"

module Participations
  class ResendsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:planning)
      @organizer_token = raw_token(:planning_organizer)
      @guest = participants(:planning_guest)
    end

    test "resend gives a linked guest a pending token and leaves the old link and the claim alone" do
      assert_difference "MailDelivery.invitation.count", 1 do
        post participation_participant_resend_path(@organizer_token, @guest)
      end

      assert_redirected_to participation_path(@organizer_token)
      assert_equal "Invitation sent again to invitee@example.com.", flash[:notice]
      @guest.reload
      assert @guest.pending_token_digest.present?
      assert_nil @guest.pending_token_expires_at
      assert_equal Participant.digest(raw_token(:planning_guest)), @guest.token_digest
      assert_equal users(:invitee).id, @guest.user_id
      assert_no_match(/\/p\/[A-Za-z0-9]{32}/, flash[:notice])
    end

    test "resend to a guest without a link issues a live token" do
      unsent = participants(:planning_unsent)

      post participation_participant_resend_path(@organizer_token, unsent)

      assert unsent.reload.token_digest.present?
      assert_nil unsent.pending_token_digest
    end

    test "cooldown applies to successful sends only" do
      post participation_participant_resend_path(@organizer_token, @guest)
      post participation_participant_resend_path(@organizer_token, @guest)
      assert_response :see_other
      assert_match(/Wait a few minutes/, flash[:alert])

      MailDelivery.invitation.update_all(failed_at: Time.current)
      post participation_participant_resend_path(@organizer_token, @guest)
      assert_equal "Invitation sent again to invitee@example.com.", flash[:notice]
    end

    test "the sixth send to one address on one event is refused" do
      5.times do |i|
        MailDelivery.create!(event: @event, participant: @guest, kind: :invitation, recipient_email: @guest.email,
          sender_email: "owner@example.com", created_at: (i + 1).hours.ago)
      end

      post participation_participant_resend_path(@organizer_token, @guest)

      assert_response :see_other
      assert_match(/maximum of 5 invitations/, flash[:alert])
    end

    test "guests and foreign ids are not found" do
      post participation_participant_resend_path(raw_token(:planning_guest), @guest)
      assert_response :not_found

      post participation_participant_resend_path(@organizer_token, participants(:finalized_guest))
      assert_response :not_found

      post participation_participant_resend_path(@organizer_token, participants(:planning_organizer))
      assert_response :not_found
    end
  end
end
