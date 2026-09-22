require "test_helper"

class ParticipationsHelperTest < ActionView::TestCase
  include EventsHelper

  test "a guest who answered reads their answer" do
    guest = participants(:planning_guest)
    assert_equal "replied (2 slots)", guest_state_label(guest, {}, slot_count: 2)

    guest.event.offer_revised_at = guest.responded_at + 1.hour
    assert_equal "replied (1 slot, before the last change)", guest_state_label(guest, {}, slot_count: 1)

    guest.reply_voided_at = Time.current
    assert_equal "needs a new reply", guest_state_label(guest, {}, slot_count: 0)

    guest.declined_at = Time.current
    assert_equal "none of these work", guest_state_label(guest, {}, slot_count: 0)

    guest.left_at = Time.current
    assert_equal "left", guest_state_label(guest, {}, slot_count: 0)
  end

  test "a guest who has not answered reads the fate of their last invitation" do
    assert_equal "not sent", guest_state_label(participants(:planning_unsent), {}, slot_count: 0)

    pending = participants(:planning_pending)
    sent = ->(**stamps) { { pending.id => [ MailDelivery.new(created_at: Time.current, **stamps) ] } }
    assert_equal "queued", guest_state_label(pending, {}, slot_count: 0)
    assert_equal "queued", guest_state_label(pending, sent.call, slot_count: 0)
    assert_equal "delivery unknown, resend", guest_state_label(pending, sent.call(created_at: 20.minutes.ago), slot_count: 0)
    assert_equal "could not be delivered", guest_state_label(pending, sent.call(failed_at: Time.current), slot_count: 0)

    delivered = guest_state_label(pending, sent.call(delivered_at: Time.utc(2030, 1, 10, 9)), slot_count: 0)
    assert_dom_equal %(sent on <time datetime="2030-01-10T09:00:00Z" class="time" data-zoned-instant="" data-zoned-format="date-time">Thu 10 Jan 2030 09:00 (UTC)</time>), delivered
  end
end
