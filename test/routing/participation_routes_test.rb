require "test_helper"

class ParticipationRoutesTest < ActionDispatch::IntegrationTest
  TOKEN = "a" * 32

  test "the token family routes every action with the viewer as :token" do
    assert_routing({ path: "/p/#{TOKEN}", method: :get }, controller: "participations", action: "show", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}", method: :patch }, controller: "participations", action: "update", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}", method: :delete }, controller: "participations", action: "destroy", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/decline", method: :post }, controller: "participations/declines", action: "create", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/finalization", method: :post }, controller: "participations/finalizations", action: "create", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/invitations", method: :post }, controller: "participations/invitations", action: "create", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/participants/7", method: :delete }, controller: "participations/participants", action: "destroy", token: TOKEN, id: "7")
    assert_routing({ path: "/p/#{TOKEN}/participants/7/resend", method: :post }, controller: "participations/resends", action: "create", token: TOKEN, participant_id: "7")
    assert_routing({ path: "/p/#{TOKEN}/participants/7/link_reveal", method: :post }, controller: "participations/link_reveals", action: "create", token: TOKEN, participant_id: "7")
    assert_routing({ path: "/p/#{TOKEN}/claim", method: :get }, controller: "participations/claims", action: "show", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/claim", method: :post }, controller: "participations/claims", action: "create", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/details/edit", method: :get }, controller: "participations/details", action: "edit", token: TOKEN)
    assert_routing({ path: "/p/#{TOKEN}/details", method: :patch }, controller: "participations/details", action: "update", token: TOKEN)

    assert_equal "/p/#{TOKEN}", participation_path(TOKEN)
    assert_equal "/p/#{TOKEN}/participants/7/resend", participation_participant_resend_path(TOKEN, 7)
    assert_equal "/p/#{TOKEN}/claim", participation_claim_path(TOKEN)
    assert_equal "/p/#{TOKEN}/details/edit", edit_participation_details_path(TOKEN)
    assert_equal "/p/#{TOKEN}/details", participation_details_path(TOKEN)
  end

  test "mangled and short tokens still reach the controller" do
    assert_recognizes({ controller: "participations", action: "show", token: "#{TOKEN}." }, "/p/#{TOKEN}.")
    assert_recognizes({ controller: "participations", action: "show", token: "#{TOKEN}.html" }, "/p/#{TOKEN}.html")
    assert_recognizes({ controller: "participations", action: "show", token: "short" }, "/p/short")
  end

  test "the session family routes every action with the viewer as :participation_id" do
    assert_routing({ path: "/participations/3", method: :get }, controller: "participations", action: "show", participation_id: "3")
    assert_routing({ path: "/participations/3", method: :patch }, controller: "participations", action: "update", participation_id: "3")
    assert_routing({ path: "/participations/3/finalization", method: :post }, controller: "participations/finalizations", action: "create", participation_id: "3")
    assert_routing({ path: "/participations/3/participants/7/resend", method: :post }, controller: "participations/resends", action: "create", participation_id: "3", participant_id: "7")
    assert_routing({ path: "/participations/3/details/edit", method: :get }, controller: "participations/details", action: "edit", participation_id: "3")
    assert_routing({ path: "/participations/3/details", method: :patch }, controller: "participations/details", action: "update", participation_id: "3")

    assert_equal "/participations/3", my_participation_path(3)
    assert_equal "/participations/3/invitations", my_participation_invitations_path(3)
    assert_equal "/participations/3/details/edit", edit_my_participation_details_path(3)
    assert_raises(NoMethodError) { my_participation_claim_path(3) }
  end

  test "legacy event routes are gone" do
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/events/1", method: :get) }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/events/1/time_slots", method: :post) }
  end
end
