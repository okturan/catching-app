# The mails one participant is sent on their own: the organizer's link, an
# invitation or its resend, and the record of a link shown to copy. Each is
# refused once the event is cancelled, before any token is issued.
module Participant::Mailings
  extend ActiveSupport::Concern

  def send_organizer_link!(request_ip:, pending: false)
    event.ensure_not_cancelled!
    token = pending ? issue_pending_token!(expires_in: 24.hours) : issue_live_token!
    MailDelivery.deliver_later(:organizer_link, to: self, token:, request_ip:)
  end

  # The first invitation of an event describes it as it stands, so the
  # guests it reaches know about every revision so far. A later invitee or a
  # resend to one guest tells nobody else, so it must not hide a change the
  # guests already linked were never told about.
  def invite!(by:, request_ip:)
    event.ensure_not_cancelled!
    MailDelivery::Caps.check_invitation!(event:, organizer: by, recipient_email: email, request_ip:)
    MailDelivery.deliver_later(:invitation, to: self, token: issue_token!, sender: by, request_ip:)
    event.mark_notified! if event.guests.active.linked.where.not(id:).none?
  end

  # Recorded, never mailed: the organizer copies the link from the page.
  def reveal_link!(by:, request_ip:)
    event.ensure_not_cancelled!
    issue_token!.tap { MailDelivery.record!(:link_shown, to: self, sender: by, request_ip:) }
  end

  # The token a mail's link carries, by the claim rule: a fresh pending one
  # for an unclaimed guest, which retires the previous pending one and leaves
  # the live link working; none for a claimed guest, whom the mailer links to
  # the signed-in page, nor for the organizer, whose copy carries no link.
  def mail_link_token!
    issue_pending_token! if guest? && !claimed?
  end
end
