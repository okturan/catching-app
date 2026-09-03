require "net/smtp"

# Delivers ParticipantMailer mails and records the outcome in the ledger row
# carried in the mailer params. Transient SMTP errors retry; permanent ones
# are discarded; both mark the row failed after the last attempt.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

  retry_on Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.mark_failed(error)
  end

  discard_on Net::SMTPFatalError, Net::SMTPAuthenticationError, Net::SMTPSyntaxError do |job, error|
    job.mark_failed(error)
  end

  def mark_failed(error)
    delivery = arguments.last.is_a?(Hash) ? arguments.last.dig(:params, :delivery) : nil
    return unless delivery.is_a?(MailDelivery)

    delivery.update_columns(failed_at: Time.current, error: "#{error.class}: #{error.message}".truncate(255))
  end
end
