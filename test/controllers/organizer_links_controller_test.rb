require "test_helper"

class OrganizerLinksControllerTest < ActionDispatch::IntegrationTest
  test "the form is public" do
    get new_organizer_link_path

    assert_response :success
    assert_select "form[action=?]", organizer_links_path
  end

  test "recovery issues a pending organizer token and touches nothing else" do
    organizer = participants(:planning_organizer)

    assert_difference "MailDelivery.organizer_link.count", 1 do
      post organizer_links_path, params: { organizer_link: { email: "Owner@example.com" } }
    end

    assert_redirected_to new_organizer_link_path
    assert_equal OrganizerLinksController::NOTICE, flash[:notice]
    organizer.reload
    assert organizer.pending_token_digest.present?
    assert_in_delta 24.hours.from_now, organizer.pending_token_expires_at, 5.seconds
    assert_equal Participant.digest(raw_token(:planning_organizer)), organizer.token_digest
    assert_equal users(:owner).id, organizer.user_id

    get participation_path(raw_token(:planning_organizer))
    assert_response :success
    sign_in users(:owner)
    get my_participation_path(organizer)
    assert_response :success
  end

  test "known, unknown and capped addresses get identical responses" do
    responses = []
    [ "owner@example.com", "nobody@example.com", "owner@example.com" ].each do |email|
      post organizer_links_path, params: { organizer_link: { email: email } }
      responses << [ response.status, response.location, flash[:notice] ]
    end

    assert_equal 1, responses.uniq.size
    assert_equal 1, MailDelivery.organizer_link.count, "the second request within the hour sends nothing"
  end

  test "finalized events get no recovery link" do
    post organizer_links_path, params: { organizer_link: { email: "owner@example.com" } }

    assert_nil participants(:finalized_organizer).reload.pending_token_digest
    assert participants(:planning_organizer).reload.pending_token_digest.present?
  end
end
