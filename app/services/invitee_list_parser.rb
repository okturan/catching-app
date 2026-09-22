# Parses the "Invite people" textarea: commas or newlines separate addresses,
# which are stripped, lowercased and deduplicated. The organizer's own address
# is dropped. Invalid addresses and oversized lists raise with a message that
# names the problem.
class InviteeListParser
  MAX_BYTES = 4096
  MAX_GUESTS = MailDelivery::Caps::GUESTS_PER_EVENT

  def self.call(text, organizer_email:)
    raise Refusal, "The invitation list is too long" if text.bytesize > MAX_BYTES

    emails = text.split(/[\n,]/).map { it.strip.downcase }.compact_blank.uniq
    emails.delete(organizer_email)

    invalid = emails.find { |email| !email.match?(Participant::EMAIL_FORMAT) || email.length > 254 }
    raise Refusal, "#{invalid} is not a valid email address" if invalid
    raise Refusal, "Invite at most #{MAX_GUESTS} people" if emails.size > MAX_GUESTS

    emails
  end
end
