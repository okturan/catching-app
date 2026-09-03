require "test_helper"

class EventSchedulingWorkflowTest < ActionDispatch::IntegrationTest
  test "organizer plans, invites, a guest replies through a link, organizer finalizes" do
    owner = users(:owner)
    berlin = ActiveSupport::TimeZone["Europe/Berlin"]
    first_time = berlin.local(2032, 3, 20, 14, 0)
    second_time = first_time + 30.minutes

    sign_in owner
    post events_path, params: {
      event: { name: "Catch up", description: "Schedule a call", slot_minutes: 30, time_zone: "Europe/Berlin" },
      invitations: { emails: "guest@example.com" },
      time_slots: { time_slot_array: [ first_time, second_time ].map(&:iso8601).join(",") }
    }
    event = Event.order(:id).last
    organizer = event.organizer
    assert_redirected_to my_participation_path(organizer)

    post my_participation_invitations_path(organizer)
    guest = event.guests.first
    assert guest.reload.token_digest.present?

    post my_participation_participant_link_reveal_path(organizer, guest)
    guest_token = response.body[%r{/p/([A-Za-z0-9]{32})}, 1]
    assert guest_token
    sign_out owner

    get participation_path(guest_token)
    assert_response :success
    patch participation_path(guest_token), params: {
      time_slots: { time_slot_array: first_time.iso8601 }, participant: { name: "Gwen", time_zone: "Asia/Tokyo" }
    }
    assert_redirected_to participation_path(guest_token)
    assert_equal [ first_time.utc ], event.mutually_available_start_times

    sign_in owner
    post my_participation_finalization_path(organizer), params: { time_slots: { time_slot_array: first_time.iso8601 } }
    assert_redirected_to my_participation_path(organizer)

    event.reload
    assert event.status?
    assert_equal first_time.utc, event.start_time
    assert_equal (first_time + 30.minutes).utc, event.end_time
    assert_equal 2, MailDelivery.finalized.where(event: event).count

    get participation_path(guest_token)
    assert_response :success
    assert_select "table#time-grid-show[data-finalized][data-role=viewer]"
    assert_select "form#availability-form", count: 0
  end
end
