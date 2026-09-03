require "test_helper"

# The accountless story: an organizer with only an email plans, opens the
# emailed link, invites, a guest replies through their link, the organizer
# finalizes, and the guest later keeps the event in a new account.
class EventSchedulingWorkflowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestCase::ClearTestDeliveries

  test "organizer and guest schedule a meeting without accounts" do
    berlin = ActiveSupport::TimeZone["Europe/Berlin"]
    first_time = berlin.local(2032, 3, 20, 14, 0)
    second_time = first_time + 30.minutes

    post events_path, params: {
      event: { name: "Catch up", description: "Schedule a call", slot_minutes: 30, time_zone: "Europe/Berlin" },
      organizer: { name: "Ann", email: "ann@example.com" },
      invitations: { emails: "guest@example.com" },
      time_slots: { time_slot_array: [ first_time, second_time ].map(&:iso8601).join(",") }
    }
    assert_redirected_to pending_events_path
    event = Event.order(:id).last
    organizer = event.organizer

    perform_enqueued_jobs
    organizer_link = link_from(ActionMailer::Base.deliveries.last, to: "ann@example.com")
    get organizer_link
    assert_response :success
    assert organizer.reload.link_opened_at.present?
    assert MailDelivery.organizer_link.last.delivered_at.present?

    post "#{organizer_link}/invitations"
    assert_redirected_to organizer_link
    perform_enqueued_jobs
    guest_link = link_from(ActionMailer::Base.deliveries.last, to: "guest@example.com")

    get guest_link
    assert_response :success
    patch guest_link, params: { time_slots: { time_slot_array: first_time.iso8601 }, participant: { name: "Gwen", time_zone: "Asia/Tokyo" } }
    assert_redirected_to guest_link
    perform_enqueued_jobs
    confirmation = ActionMailer::Base.deliveries.last
    assert_equal [ "guest@example.com" ], confirmation.to
    assert_match "your reply to Catch up is saved", confirmation.subject
    assert_equal [ first_time.utc ], event.mutually_available_start_times

    post "#{organizer_link}/finalization", params: { time_slots: { time_slot_array: first_time.iso8601 } }
    assert_redirected_to organizer_link
    perform_enqueued_jobs
    event.reload
    assert event.status?
    assert_equal first_time.utc, event.start_time
    assert_equal (first_time + 30.minutes).utc, event.end_time
    finalized = ActionMailer::Base.deliveries.last(2)
    assert_equal [ "ann@example.com", "guest@example.com" ], finalized.flat_map(&:to).sort
    assert finalized.all? { |mail| mail.subject.include?("Catch up is set for Sat 20 Mar") }

    get guest_link
    assert_select "table#time-grid-show[data-finalized][data-role=viewer]"
    assert_select "form#availability-form", count: 0

    get "#{guest_link}/claim"
    assert_redirected_to new_user_session_path
    post user_registration_path, params: { user: {
      first_name: "Gwen", last_name: "Guest", email: "gwen@example.com",
      password: "correct horse battery staple", password_confirmation: "correct horse battery staple"
    } }
    assert_redirected_to "#{guest_link}/claim"
    follow_redirect!
    post "#{guest_link}/claim"
    guest = event.guests.first
    assert_redirected_to my_participation_path(guest)
    assert_equal User.find_by(email: "gwen@example.com"), guest.reload.user
  end

  private

  def link_from(mail, to:)
    assert_equal [ to ], mail.to
    mail.text_part.body.to_s[%r{/p/[A-Za-z0-9]{32}}] or flunk("no link in mail to #{to}")
  end
end
