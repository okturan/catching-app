require "test_helper"

class MailDeliveryTest < ActiveSupport::TestCase
  setup do
    @event = events(:planning)
    @organizer = participants(:planning_organizer)
  end

  def record(kind: :invitation, recipient: "guest@example.com", sender: @organizer.email, event: @event, created_at: Time.current, failed_at: nil, request_ip: nil)
    MailDelivery.create!(event: event, participant: nil, kind: kind, recipient_email: recipient,
      sender_email: MailDelivery.canonical(sender), created_at: created_at, failed_at: failed_at, request_ip: request_ip)
  end

  def check!(recipient: "guest@example.com", request_ip: nil)
    MailDelivery::Caps.check_invitation!(event: @event, organizer: @organizer, recipient_email: recipient, request_ip: request_ip)
  end

  test "canonical addresses drop plus tags and gmail dots" do
    assert_equal "spam@example.com", MailDelivery.canonical("Spam+1@Example.com")
    assert_equal "johndoe@gmail.com", MailDelivery.canonical("john.doe+news@gmail.com")
    assert_equal "john.doe@example.com", MailDelivery.canonical("john.doe@example.com")
  end

  test "state follows the ledger columns" do
    row = record
    assert_equal :queued, row.state
    row.update!(delivered_at: Time.current)
    assert_equal :delivered, row.state
    row.update!(failed_at: Time.current)
    assert_equal :failed, row.state
    assert_equal :unknown, record(created_at: 20.minutes.ago).state
  end

  test "the global daily budget stops the cannon" do
    ENV["INVITATION_DAILY_BUDGET"] = "2"
    2.times { |i| record(recipient: "g#{i}@example.com") }

    assert_raises(MailDelivery::CapExceeded) { check!(recipient: "new@example.com") }
  ensure
    ENV.delete("INVITATION_DAILY_BUDGET")
  end

  test "an organizer without a finalized event gets the starter allowance" do
    starter = participants(:other_organizer)
    20.times { |i| record(recipient: "g#{i}@example.com", sender: starter.email, event: events(:other_event)) }
    assert_raises(MailDelivery::CapExceeded) do
      MailDelivery::Caps.check_invitation!(event: events(:other_event), organizer: starter, recipient_email: "new@example.com", request_ip: nil)
    end

    # owner@example.com organizes the finalized fixture event, so it has the full allowance.
    20.times { |i| record(recipient: "g#{i}@example.com") }
    assert_nothing_raised { check!(recipient: "new@example.com") }
  end

  test "plus addressing shares one allowance" do
    starter = participants(:other_organizer)
    20.times { |i| record(recipient: "g#{i}@example.com", sender: "other-owner+#{i}@example.com", event: events(:other_event)) }

    assert_raises(MailDelivery::CapExceeded) do
      MailDelivery::Caps.check_invitation!(event: events(:other_event), organizer: starter, recipient_email: "new@example.com", request_ip: nil)
    end
  end

  test "per recipient, per address-and-event, cooldown and IP caps" do
    10.times { |i| record(recipient: "busy@example.com", sender: "o#{i}@example.com", event: events(:other_event)) }
    assert_raises(MailDelivery::CapExceeded) { check!(recipient: "busy@example.com") }

    record(recipient: "fresh@example.com", created_at: 2.minutes.ago)
    assert_raises(MailDelivery::CapExceeded) { check!(recipient: "fresh@example.com") }

    record(recipient: "failed@example.com", created_at: 1.minute.ago, failed_at: Time.current)
    assert_nothing_raised { check!(recipient: "failed@example.com") }

    5.times { |i| record(recipient: "capped@example.com", created_at: (i + 1).hours.ago) }
    assert_raises(MailDelivery::CapExceeded) { check!(recipient: "capped@example.com") }

    200.times { |i| record(recipient: "ip#{i}@example.com", sender: "s#{i % 30}@example.com", request_ip: "203.0.113.9") }
    assert_raises(MailDelivery::CapExceeded) { check!(recipient: "another@example.com", request_ip: "203.0.113.9") }
  end

  test "organizer link mails are limited to one per address per hour" do
    assert MailDelivery::Caps.organizer_link_allowed?("owner@example.com")
    record(kind: :organizer_link, recipient: "Owner+x@example.com", sender: nil)
    assert_not MailDelivery::Caps.organizer_link_allowed?("owner@example.com")
  end

  test "event creation caps count opened events per address and unopened per IP" do
    5.times do |i|
      event = Event.create!(name: "E#{i}", description: "d", slot_minutes: 60, time_zone: "UTC")
      event.participants.create!(role: :organizer, email: "busy+#{i}@example.com", name: "B", link_opened_at: Time.current, responded_at: Time.current)
    end
    assert_raises(MailDelivery::CapExceeded) do
      MailDelivery::Caps.check_event_creation!(organizer_email: "busy@example.com", request_ip: "198.51.100.1")
    end

    3.times do |i|
      event = Event.create!(name: "U#{i}", description: "d", slot_minutes: 60, time_zone: "UTC")
      event.participants.create!(role: :organizer, email: "victim@example.com", name: "V", responded_at: Time.current)
    end
    assert_raises(MailDelivery::CapExceeded) do
      MailDelivery::Caps.check_event_creation!(organizer_email: "victim@example.com", request_ip: "198.51.100.2")
    end
    assert_nothing_raised do
      MailDelivery::Caps.check_event_creation!(organizer_email: "someone-else@example.com", request_ip: "198.51.100.2")
    end
  end
end
