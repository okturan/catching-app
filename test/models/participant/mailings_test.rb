require "test_helper"

class Participant::MailingsTest < ActiveSupport::TestCase
  setup do
    @event = events(:planning)
    @organizer = participants(:planning_organizer)
    @guest = participants(:planning_guest)
  end

  test "each is refused once the event is cancelled, before any token is issued" do
    @event.cancel!
    unsent = participants(:planning_unsent)
    calls = {
      "invite!" => -> { unsent.invite!(by: @organizer, request_ip: "203.0.113.1") },
      "send_organizer_link!" => -> { @organizer.send_organizer_link!(request_ip: nil, pending: true) },
      "reveal_link!" => -> { @guest.reveal_link!(by: @organizer, request_ip: nil) }
    }

    assert_no_difference "MailDelivery.count" do
      assert_no_enqueued_jobs do
        calls.each do |name, call|
          error = assert_raises(Event::Closed, name) { call.call }
          assert_equal "This event was cancelled", error.message, name
        end
      end
    end
    assert_nil unsent.reload.token_digest
    assert_nil @organizer.reload.pending_token_digest
    assert_nil @guest.reload.pending_token_digest
  end

  test "the first invitation marks the guests told about every revision so far; later invitees and resends tell nobody else" do
    @event.update_columns(revision: 3, notified_revision: 1)
    unsent = participants(:planning_unsent)

    unsent.invite!(by: @organizer, request_ip: "203.0.113.1")
    assert_equal 1, @event.reload.notified_revision, "two guests already linked were never told about revisions 2 and 3"
    assert unsent.reload.token_digest.present?

    @event.guests.where.not(id: unsent.id).update_all(token_digest: nil)
    MailDelivery.invitation.delete_all
    unsent.invite!(by: @organizer, request_ip: "203.0.113.1")
    assert_equal 3, @event.reload.notified_revision, "the only linked guest now knows the current state"

    @event.update_columns(revision: 4)
    MailDelivery.invitation.delete_all
    @guest.invite!(by: @organizer, request_ip: "203.0.113.1")
    assert_equal 3, @event.reload.notified_revision, "a late invitee does not hide what the first guest was never told"
  end
end
