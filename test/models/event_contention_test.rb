require "test_helper"

# Runs outside transactional tests so a second connection can contend for
# the event row lock.
class EventContentionTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @event = Event.plan!(
      attributes: { name: "Contention", description: "lock test", slot_minutes: 60, time_zone: "UTC" },
      organizer: { email: "lock-organizer@example.com", name: "Lock", user: nil },
      starts_at: [ Time.utc(2031, 3, 1, 10) ],
      invitee_emails: [ "lock-guest@example.com" ]
    )
    @guest = @event.guests.first
    @event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2031, 3, 1, 10) ])
    @guest.update!(responded_at: Time.current)
  end

  teardown do
    Event.where(id: @event.id).destroy_all
  end

  test "finalize! waits for a concurrent decline and then observes it" do
    locked = Queue.new
    release = Queue.new

    decliner = Thread.new do
      Event.find(@event.id).with_lock do
        locked << true
        release.pop
        Participant.where(id: @guest.id).update_all(declined_at: Time.current)
      end
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end

    locked.pop
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    finalizer = Thread.new do
      Event.find(@event.id).finalize!(starts_at: [ Time.utc(2031, 3, 1, 10) ])
    rescue ArgumentError => error
      error
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end

    sleep 0.3
    release << true
    result = finalizer.value
    decliner.join
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :>=, 0.25, "finalize! should have blocked on the row lock"
    assert_kind_of ArgumentError, result
    assert_equal "Wait for at least one reply before confirming", result.message
    assert_not @event.reload.status?
  end
end
