# The mails one participant is sent on their own, each refused once the
# event is cancelled, before any token is issued.
module Participant::Mailings
  extend ActiveSupport::Concern

  def send_organizer_link!(request_ip:, pending: false)
    event.ensure_not_cancelled!
    token = pending ? issue_pending_token!(expires_in: 24.hours) : issue_live_token!
    MailDelivery.deliver_later(:organizer_link, to: self, token:, request_ip:)
  end

  # Only the first invitation of an event marks the guests told: a later one
  # must not hide changes the guests already linked never heard about.
  def invite!(by:, request_ip:)
    event.ensure_not_cancelled!
    MailDelivery::Caps.check_invitation!(event:, organizer: by, recipient_email: email, request_ip:)
    MailDelivery.deliver_later(:invitation, to: self, token: issue_token!, sender: by, request_ip:)
    event.mark_notified! if event.guests.active.linked.where.not(id:).none?
  end

  # Recorded, never mailed.
  def reveal_link!(by:, request_ip:)
    event.ensure_not_cancelled!
    issue_token!.tap { MailDelivery.record!(:link_shown, to: self, sender: by, request_ip:) }
  end

  # The claim rule: a fresh pending token for an unclaimed guest; none for a
  # claimed guest, whose mail links their account, nor for the organizer.
  def mail_link_token!
    issue_pending_token! if guest? && !claimed?
  end
end
