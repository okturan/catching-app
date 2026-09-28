require "net/smtp"

# Records each mail's fate in its ledger row. A guest removed while the mail
# was queued is not written to.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

  before_perform { throw :abort unless delivery.participant }

  retry_on Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.mark_failed(error)
  end

  discard_on Net::SMTPFatalError, Net::SMTPAuthenticationError, Net::SMTPSyntaxError do |job, error|
    job.mark_failed(error)
  end

  def mark_failed(error)
    delivery.update_columns(failed_at: Time.current, error: "#{error.class}: #{error.message}".truncate(255))
  end

  private

  def delivery
    arguments.last.dig(:params, :delivery)
  end
end
