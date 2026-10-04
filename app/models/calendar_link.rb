# The calendar file a mail offers, behind a signed URL instead of an
# attachment: the mail service sends no attachments. The signature carries
# what the mail was queued with (window, status, sequence), so a link from an
# old mail still gives the file that mail described. It opens no participant
# page, so a cancellation mail, which carries no link, can carry this one.
#
# A token is "<event>.<start>.<end>.<status>.<sequence>.<expiry>.<mac>": the
# numbers in base 36, the MAC a truncated HMAC-SHA256 over the rest.
class CalendarLink
  STATUSES = { "c" => :confirmed, "x" => :cancelled }.freeze
  LIFETIME = 1.year
  MAC_BYTES = 16

  def self.token_for(event, window:, status:, sequence:, now: Time.current)
    fields = [ event.id, *window.map(&:to_i), (now + LIFETIME).to_i ].map { it.to_s(36) }
    body = [ *fields[0, 3], STATUSES.key(status.to_sym), (sequence || event.revision).to_i.to_s(36), fields[3] ].join(".")
    "#{body}.#{mac(body)}"
  end

  # Nil for a tampered, expired or unknown link.
  def self.file_for(token, now: Time.current)
    body, _, given = token.to_s.rpartition(".")
    return unless body.present? && ActiveSupport::SecurityUtils.secure_compare(mac(body), given)

    id, start, finish, status, sequence, expiry = body.split(".")
    return if expiry.to_i(36) < now.to_i || !STATUSES.key?(status)

    event = Event.find_by(id: id.to_i(36))
    return unless event

    CalendarFile.new(event, mode: :mail, window: [ Time.at(start.to_i(36)).utc, Time.at(finish.to_i(36)).utc ],
      status: STATUSES.fetch(status), sequence: sequence.to_i(36))
  end

  def self.mac(body)
    key = Rails.application.key_generator.generate_key("calendar_link")
    Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", key, body)[0, MAC_BYTES], padding: false)
  end
  private_class_method :mac
end
