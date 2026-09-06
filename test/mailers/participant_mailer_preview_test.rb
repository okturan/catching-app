require "test_helper"
require Rails.root.join("test/mailers/previews/participant_mailer_preview").to_s

# The previews are development tooling, but a preview that raises is found
# only by someone opening it; this renders every sample against the fixture
# database instead.
class ParticipantMailerPreviewTest < ActiveSupport::TestCase
  test "every mailer action has a preview and every preview renders both parts" do
    names = ParticipantMailerPreview.emails
    ParticipantMailer.public_instance_methods(false).map(&:to_s).grep_v(/\A_/).sort.each do |action|
      assert names.any? { |name| name == action || name.start_with?("#{action}_") }, "no preview for #{action}"
    end

    names.each do |name|
      mail = ParticipantMailerPreview.call(name)
      assert mail.subject.start_with?("Catching App: "), "#{name}: #{mail.subject}"
      assert_not_empty mail.to, name
      assert_not_empty mail.html_part.body.to_s.strip, "#{name}: empty html part"
      assert_not_empty mail.text_part.body.to_s.strip, "#{name}: empty text part"
    end
  end

  test "the samples show a place, a plan, the voided guest and the calendar files without writing anything" do
    event = Event.order(:id).first
    before = [ Event.count, Participant.count, Activity.count, MailDelivery.count, event.attributes ]

    finalized = ParticipantMailerPreview.call("finalized").text_part.body.to_s
    assert_includes finalized, "Where: "
    assert_includes finalized, "How long: "
    assert_match(/^Plan:\n1\. .+ \(\d+ min\) at \d{2}:\d{2} \(/, finalized)
    assert_equal [ "catching-app.ics" ], ParticipantMailerPreview.call("finalized").attachments.map(&:filename)
    assert_not_includes ParticipantMailerPreview.call("finalized_organizer_copy").text_part.body.to_s, "Leave this event"

    voided = ParticipantMailerPreview.call("event_updated_offer_voided").text_part.body.to_s
    assert_includes voided, "None of the times you picked are offered any more. Please pick again."
    stale = ParticipantMailerPreview.call("event_updated_offer").text_part.body.to_s
    assert_includes stale, "Some of the offered times changed (2 added, 1 removed)."
    assert_includes ParticipantMailerPreview.call("event_updated_details").text_part.body.to_s, "The event is now called"

    cancelled = ParticipantMailerPreview.call("cancelled")
    assert_includes cancelled.attachments.first.body.decoded, "STATUS:CANCELLED"
    assert_empty ParticipantMailerPreview.call("cancelled_while_pending").attachments
    assert_includes ParticipantMailerPreview.call("reopened").attachments.first.body.decoded, "STATUS:CANCELLED"

    assert_equal before, [ Event.count, Participant.count, Activity.count, MailDelivery.count, event.reload.attributes ]
  end
end
