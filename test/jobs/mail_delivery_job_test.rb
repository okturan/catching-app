require "test_helper"

class MailDeliveryJobTest < ActiveJob::TestCase
  class BusyDelivery
    def initialize(*) = nil

    def deliver!(_mail)
      raise Net::SMTPServerBusy, "451 try again later"
    end
  end

  setup do
    ActionMailer::Base.add_delivery_method :busy, BusyDelivery
    @previous = ParticipantMailer.delivery_method
    ParticipantMailer.delivery_method = :busy
    @row = MailDelivery.create!(event: events(:planning), participant: participants(:planning_organizer),
      kind: :organizer_link, recipient_email: "owner@example.com")
  end

  teardown do
    ParticipantMailer.delivery_method = @previous
  end

  test "transient SMTP failures retry and then mark the ledger row failed" do
    ParticipantMailer.with(delivery: @row, token: "t" * 32).organizer_link.deliver_later

    assert_enqueued_jobs 1, only: MailDeliveryJob
    3.times { perform_enqueued_jobs }

    @row.reload
    assert @row.failed_at.present?
    assert_match(/SMTPServerBusy/, @row.error)
    assert_nil @row.delivered_at
    assert_no_enqueued_jobs only: MailDeliveryJob
  end

  test "the job never logs its arguments and is the configured delivery job" do
    assert_equal false, MailDeliveryJob.log_arguments
    assert_equal MailDeliveryJob, ParticipantMailer.delivery_job
  end
end
