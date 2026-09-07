require "test_helper"

module Participations
  class ClaimsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @pending = participants(:planning_pending)
      @token = raw_token(:planning_pending)
    end

    test "the claim CTA appears only on unclaimed token pages" do
      get participation_path(@token)
      assert_select "a[href=?]", participation_claim_path(@token)

      get participation_path(raw_token(:planning_guest))
      assert_select "a[href=?]", participation_claim_path(raw_token(:planning_guest)), count: 0
    end

    test "claiming needs a session and comes back after sign-in" do
      get participation_claim_path(@token)
      assert_redirected_to new_user_session_path

      sign_in users(:outsider)
      get participation_claim_path(@token)
      assert_response :success
      assert_select "form[action=?]", participation_claim_path(@token)
    end

    test "a signed-in user claims by token possession" do
      sign_in users(:outsider)

      post participation_claim_path(@token)

      assert_redirected_to my_participation_path(@pending)
      assert_equal users(:outsider).id, @pending.reload.user_id

      post participation_claim_path(@token)
      assert_redirected_to my_participation_path(@pending)
      assert_equal "This event is already in your account.", flash[:notice]
    end

    test "another account cannot take a claimed participation" do
      @pending.update!(user: users(:outsider))
      sign_in users(:other_owner)

      post participation_claim_path(@token)

      assert_response :unprocessable_entity
      assert_match "This invitation is already linked to another account", response.body
      assert_equal users(:outsider).id, @pending.reload.user_id
    end

    test "one account cannot hold two participations on one event" do
      sign_in users(:invitee)

      post participation_claim_path(@token)

      assert_response :unprocessable_entity
      assert_match "You already take part in this event as invitee@example.com", response.body
      assert_nil @pending.reload.user_id
    end

    test "a matching email never auto-claims" do
      users(:outsider).update!(email: "pending@example.com")
      sign_in users(:outsider)

      get participation_path(@token)

      assert_nil @pending.reload.user_id
    end
  end
end
