require "test_helper"

class ParticipantRoutesTest < ActionDispatch::IntegrationTest
  TOKEN = "a" * 32

  # A link's token and a signed-in participant's id share every route.
  test "every action lives under /p/:key, whatever the key" do
    [ TOKEN, "3" ].each do |key|
      assert_routing({ path: "/p/#{key}", method: :get }, controller: "participants", action: "show", key:)
      assert_routing({ path: "/p/#{key}", method: :patch }, controller: "participants", action: "update", key:)
      assert_routing({ path: "/p/#{key}", method: :delete }, controller: "participants", action: "destroy", key:)
      assert_routing({ path: "/p/#{key}/decline", method: :post }, controller: "participants/declines", action: "create", key:)
      assert_routing({ path: "/p/#{key}/finalization", method: :post }, controller: "participants/finalizations", action: "create", key:)
      assert_routing({ path: "/p/#{key}/invitations", method: :post }, controller: "participants/invitations", action: "create", key:)
      assert_routing({ path: "/p/#{key}/guests/7", method: :delete }, controller: "participants/guests", action: "destroy", key:, id: "7")
      assert_routing({ path: "/p/#{key}/guests/7/resend", method: :post }, controller: "participants/resends", action: "create", key:, guest_id: "7")
      assert_routing({ path: "/p/#{key}/guests/7/link_reveal", method: :post }, controller: "participants/link_reveals", action: "create", key:, guest_id: "7")
      assert_routing({ path: "/p/#{key}/claim", method: :get }, controller: "participants/claims", action: "show", key:)
      assert_routing({ path: "/p/#{key}/claim", method: :post }, controller: "participants/claims", action: "create", key:)
      assert_routing({ path: "/p/#{key}/details/edit", method: :get }, controller: "participants/details", action: "edit", key:)
      assert_routing({ path: "/p/#{key}/details", method: :patch }, controller: "participants/details", action: "update", key:)
      assert_routing({ path: "/p/#{key}/offer/edit", method: :get }, controller: "participants/offers", action: "edit", key:)
      assert_routing({ path: "/p/#{key}/offer", method: :patch }, controller: "participants/offers", action: "update", key:)
      assert_routing({ path: "/p/#{key}/notice", method: :post }, controller: "participants/notices", action: "create", key:)
      assert_routing({ path: "/p/#{key}/cancellation", method: :post }, controller: "participants/cancellations", action: "create", key:)
      assert_routing({ path: "/p/#{key}/reopening", method: :post }, controller: "participants/reopenings", action: "create", key:)
      assert_routing({ path: "/p/#{key}/calendar.ics", method: :get }, controller: "participants/calendars", action: "show", key:)
      assert_routing({ path: "/p/#{key}/plan", method: :post }, controller: "participants/plan_items", action: "create", key:)
      assert_routing({ path: "/p/#{key}/plan/7", method: :patch }, controller: "participants/plan_items", action: "update", key:, id: "7")
      assert_routing({ path: "/p/#{key}/plan/7", method: :delete }, controller: "participants/plan_items", action: "destroy", key:, id: "7")
      assert_routing({ path: "/p/#{key}/plan/7/move", method: :post }, controller: "participants/plan_item_moves", action: "create", key:, plan_item_id: "7")
    end
  end

  test "a participant found by a link builds its paths with that link's token, otherwise with its id" do
    participant = participants(:planning_guest)
    assert_equal "/p/#{participant.id}/details/edit", edit_participant_details_path(participant)
    assert_equal "/p/#{participant.id}/guests/7/resend", participant_guest_resend_path(participant, 7)

    participant.link_token = TOKEN
    assert_equal "/p/#{TOKEN}", participant_path(participant)
    assert_equal "/p/#{TOKEN}/plan/7/move", participant_plan_item_move_path(participant, 7)
  end

  test "mangled and short keys still reach the controller" do
    assert_recognizes({ controller: "participants", action: "show", key: "#{TOKEN}." }, "/p/#{TOKEN}.")
    assert_recognizes({ controller: "participants", action: "show", key: "#{TOKEN}.html" }, "/p/#{TOKEN}.html")
    assert_recognizes({ controller: "participants", action: "show", key: "short" }, "/p/short")
  end

  test "legacy event routes are gone" do
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/events/1", method: :get) }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/events/1/time_slots", method: :post) }
  end

  test "the account-only activities routes are gone" do
    [ [ "/events/1/activities", :get ], [ "/events/1/activities", :post ], [ "/events/1/activities/new", :get ], [ "/events/1/activities/2", :get ] ].each do |path, method|
      assert_raises(ActionController::RoutingError, "#{method.upcase} #{path} still routes") do
        Rails.application.routes.recognize_path(path, method: method)
      end
    end
    assert_raises(NoMethodError) { event_activities_path(1) }
  end
end
