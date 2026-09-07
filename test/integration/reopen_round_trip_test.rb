require "test_helper"

# Finalize, reopen, revise the offer, finalize, reopen, finalize: three
# finalized batches at most, each file outranking the one before, the
# withdrawn windows cleared by cancelled files in between, and the third
# reopen refused.
class ReopenRoundTripTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestCase::ClearTestDeliveries

  setup do
    @event = events(:planning)
    @organizer_token = raw_token(:planning_organizer)
    @guest_token = raw_token(:planning_guest)
    # Fixture replies are dated 2030; the guest replied before today's reopen.
    participants(:planning_guest).update_columns(responded_at: 2.days.ago)
    @ten = "2030-01-15T10:00:00Z"
    @eleven = "2030-01-15T11:00:00Z"
    @twelve = "2030-01-15T12:00:00Z"
  end

  def finalize!(slot)
    perform_enqueued_jobs { post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: slot } } }
    assert_equal "Meeting time confirmed.", flash[:notice]
    assert @event.reload.status?
  end

  def reopen!
    perform_enqueued_jobs { post participation_reopening_path(@organizer_token) }
    assert_match(/\AThe set time was withdrawn\. 2 guests were told\./, flash[:notice])
    assert_not @event.reload.status?
  end

  def sequence_of(mail)
    mail.attachments.first.body.decoded[/SEQUENCE:(\d+)/, 1].to_i
  end

  def guest_mails(kind)
    MailDelivery.where(kind: kind, recipient_email: "invitee@example.com").count
  end

  test "finalize, reopen, revise, finalize, reopen, finalize sends three finalized batches and refuses a fourth reopen" do
    finalize!(@ten)
    first = ActionMailer::Base.deliveries.last(3)
    assert_equal %w[invitee@example.com owner@example.com pending@example.com], first.flat_map(&:to).sort
    get participation_calendar_path(@guest_token)
    assert_response :success

    reopen!
    assert_equal 1, @event.reopen_count
    withdrawn = ActionMailer::Base.deliveries.last(2)
    assert_equal %w[invitee@example.com pending@example.com], withdrawn.flat_map(&:to).sort
    withdrawn.each do |mail|
      assert_includes mail.attachments.first.body.decoded, "STATUS:CANCELLED"
      assert_includes mail.attachments.first.body.decoded, "DTSTART:20300115T100000Z"
    end
    get participation_calendar_path(@guest_token)
    assert_response :not_found
    get participation_path(@guest_token)
    assert_select ".grid-notice", text: /The set time was withdrawn on/
    assert_select "#my-time-slots[value=?]", [ @ten ].to_json

    patch participation_offer_path(@organizer_token), params: { time_slots: { time_slot_array: [ @ten, @eleven, @twelve ].join(",") }, notice: { send: "0" } }
    assert_equal "Times updated: 1 added, 0 removed.", flash[:notice]
    assert_equal 0, MailDelivery.event_updated.count
    patch participation_path(@guest_token), params: { time_slots: { time_slot_array: [ @ten, @twelve ].join(",") } }
    assert_equal "Availability saved.", flash[:notice]
    get participation_path(@guest_token)
    assert_select ".grid-notice", count: 0
    assert_equal [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 12) ], @event.mutually_available_start_times

    finalize!(@twelve)
    assert_equal Time.utc(2030, 1, 15, 12), @event.start_time
    second = ActionMailer::Base.deliveries.last(3)
    assert second.all? { |mail| mail.attachments.first.body.decoded.include?("DTSTART:20300115T120000Z") }

    reopen!
    assert_equal 2, @event.reopen_count
    get participation_path(@organizer_token)
    assert_select ".event-reopened span", text: "Reopened twice — the last time"

    finalize!(@ten)
    third = ActionMailer::Base.deliveries.last(3)

    post participation_reopening_path(@organizer_token)
    assert_response :see_other
    assert_equal "This event was reopened twice already. Cancel it and plan a new one.", flash[:alert]
    @event.reload
    assert @event.status?
    assert_equal Time.utc(2030, 1, 15, 10), @event.start_time
    assert_equal 2, @event.reopen_count

    assert_equal 3, guest_mails(:finalized), "three finalized batches"
    assert_equal 2, guest_mails(:reopened)
    assert_equal 9, MailDelivery.finalized.count
    assert_equal 4, MailDelivery.reopened.count
    assert MailDelivery.where(kind: %w[finalized reopened]).all? { |row| row.delivered_at.present? }

    to_guest = ->(mails) { mails.find { |mail| mail.to == [ "invitee@example.com" ] } }
    sequences = [ first, second, third ].map { |batch| sequence_of(to_guest.call(batch)) }
    assert_equal sequences.sort, sequences
    assert_equal sequences.uniq, sequences, "every finalized file outranks the one before"
    withdrawn_sequence = sequence_of(to_guest.call(withdrawn))
    assert_operator withdrawn_sequence, :>, sequences[0]
    assert_operator withdrawn_sequence, :<, sequences[1]
    last_file = to_guest.call(third).attachments.first.body.decoded
    assert_includes last_file, "STATUS:CONFIRMED"
    assert_includes last_file, "SEQUENCE:#{@event.revision}"
    assert_equal @event.revision, @event.notified_revision
    uids = [ first, second, third ].map { |batch| to_guest.call(batch).attachments.first.body.decoded[/UID:(\S+)/, 1] }
    assert_equal 1, uids.uniq.size, "one calendar entry for the life of the event"
  end
end
