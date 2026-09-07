require "test_helper"

module Participations
  class LinkRevealsControllerTest < ActionDispatch::IntegrationTest
    test "the link is shown once as text and recorded" do
      organizer_token = raw_token(:planning_organizer)
      pending = participants(:planning_pending)

      assert_difference "MailDelivery.link_shown.count", 1 do
        post participation_participant_link_reveal_path(organizer_token, pending)
      end

      assert_response :success
      url = response.body[%r{http://[^"<\s]+/p/[A-Za-z0-9]{32}}]
      assert url, "the revealed URL is printed"
      assert_select "a[href=?]", url, count: 0

      get participation_path(organizer_token)
      assert_no_match url, response.body

      raw = url.split("/p/").last
      get participation_path(raw)
      assert_response :success
    end

    test "guest tokens cannot reveal links" do
      post participation_participant_link_reveal_path(raw_token(:planning_guest), participants(:planning_pending))

      assert_response :not_found
    end
  end
end
