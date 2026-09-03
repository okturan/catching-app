require "test_helper"

module Participations
  class InvitationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = events(:planning)
      @organizer_token = raw_token(:planning_organizer)
    end

    test "sending issues tokens for unsent active guests only and records the ledger" do
      unsent = participants(:planning_unsent)
      pending = participants(:planning_pending)

      assert_difference "MailDelivery.invitation.count", 1 do
        post participation_invitations_path(@organizer_token)
      end

      assert_redirected_to participation_path(@organizer_token)
      assert_equal "1 invitation sent.", flash[:notice]
      assert unsent.reload.token_digest.present?
      assert_equal Participant.digest(raw_token(:planning_pending)), pending.reload.token_digest
      assert_nil participants(:planning_left).reload.token_digest
      assert_equal "owner@example.com", MailDelivery.invitation.last.sender_email
    end

    test "inviting more people deduplicates and names conflicts" do
      post participation_invitations_path(@organizer_token), params: {
        invitations: { emails: "New.Person@example.com\ninvitee@example.com, left@example.com" }
      }

      assert_redirected_to participation_path(@organizer_token)
      assert_match "1 added.", flash[:notice]
      assert_match "invitee@example.com and left@example.com already on this event.", flash[:notice]
      assert @event.participants.exists?(email: "new.person@example.com", role: "guest")
    end

    test "an event never exceeds fifty guests" do
      (50 - @event.guests.active.count).times { |i| @event.participants.create!(role: :guest, email: "bulk#{i}@example.com") }

      post participation_invitations_path(@organizer_token), params: { invitations: { emails: "one-more@example.com" } }

      assert_response :see_other
      assert_match(/at most 50 guests/, flash[:alert])
      assert_not @event.participants.exists?(email: "one-more@example.com")
    end

    test "a guest token cannot send invitations" do
      post participation_invitations_path(raw_token(:planning_guest))

      assert_response :not_found
    end

    test "an invalid address is named" do
      post participation_invitations_path(@organizer_token), params: { invitations: { emails: "not-an-address" } }

      assert_response :see_other
      assert_equal "not-an-address is not a valid email address", flash[:alert]
    end
  end
end
