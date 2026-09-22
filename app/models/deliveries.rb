# Every transactional mail goes through here: caps are checked, the token is
# issued, the ledger row is written, and the mail is enqueued. Once an event
# is cancelled only cancelled! passes; every other kind raises, so no later
# action can put mail about a cancelled event in anyone's inbox.
module Deliveries
  extend self

  # How far a change notice reached, in the words the organizer reads.
  Report = Data.define(:sent, :skipped) do
    def reached_anyone? = (sent + skipped).positive?

    def to_s
      [ "#{sent} #{"guest".pluralize(sent)} emailed.",
        ("#{skipped} skipped (recently notified). Try again after 10 minutes." if skipped.positive?) ].compact.join(" ")
    end
  end

  def invitation!(event:, guest:, organizer:, request_ip:)
    event.ensure_not_cancelled!
    MailDelivery::Caps.check_invitation!(event:, organizer:, recipient_email: guest.email, request_ip:)
    mail!(:invitation, event:, to: guest, token: guest.issue_token!, sender: organizer, request_ip:)
    # The first invitation of an event describes it as it stands, so the
    # guests it reaches know about every revision so far. A later invitee or
    # a Resend to one guest tells nobody else, so it must not hide a change
    # the guests already linked were never told about.
    mark_notified(event) if event.guests.active.linked.where.not(id: guest.id).none?
  end

  def organizer_link!(event:, organizer:, request_ip:, pending: false)
    event.ensure_not_cancelled!
    token = pending ? organizer.issue_pending_token!(expires_in: 24.hours) : organizer.issue_live_token!
    mail!(:organizer_link, event:, to: organizer, token:, request_ip:)
  end

  def response_confirmation!(event:, guest:)
    event.ensure_not_cancelled!
    mail!(:response_confirmation, event:, to: guest)
  end

  # After finalize!: everyone active with a link, the organizer included as
  # a receipt, never capped. The set window travels in the params so a
  # retried job never reads the row, and the batch marks the guests as told
  # about this revision.
  def finalized!(event:)
    event.ensure_not_cancelled!
    window = [ event.start_time, event.end_time ]
    event.participants.active.linked.each do |participant|
      mail!(:finalized, event:, to: participant, token: link_token!(participant), window:, sequence: event.revision)
    end
    mark_notified(event)
  end

  # One coalesced change notice, only when the organizer asks (the details
  # checkbox, the offer checkbox or Tell the guests). Recipients are active
  # linked guests; an offer notice goes only to guests who already replied,
  # and skips declined guests when nothing was added. A recipient over the
  # notice caps is skipped and counted. The organizer never receives one.
  def event_updated!(event:, organizer:, request_ip:, reason:, changes: nil)
    event.ensure_not_cancelled!
    raise Refusal, "Open your organizer link before emailing guests" unless organizer.link_opened_at?

    sent = skipped = 0
    notice_recipients(event, reason).each do |guest|
      MailDelivery::Caps.check_update_notice!(event:, organizer:, recipient_email: guest.email, request_ip:)
    rescue MailDelivery::CapExceeded
      skipped += 1
    else
      mail!(:event_updated, event:, to: guest, token: link_token!(guest), sender: organizer, request_ip:, reason:, changes:)
      sent += 1
    end
    mark_notified(event) if sent.positive?
    Report.new(sent:, skipped:)
  end

  # Recorded, never mailed: the organizer copies the link from the page.
  def reveal_link!(event:, guest:, organizer:, request_ip:)
    event.ensure_not_cancelled!
    guest.issue_token!.tap do
      MailDelivery.create!(event:, participant: guest, kind: :link_shown, recipient_email: guest.email,
        sender_email: organizer.email, request_ip:)
    end
  end

  # The one last mail: everyone active with a link, declined guests and the
  # organizer included, left and never-invited excluded. No token, no link,
  # no cap. The set window, when there was one, travels in the params so a
  # retried job never reads the live row. Returns the number of people told.
  def cancelled!(event:)
    window = [ event.start_time, event.end_time ] if event.finalized?
    told = event.participants.active.linked.to_a
    told.each { mail!(:cancelled, event:, to: it, sender: event.organizer, window:, sequence: event.revision) }
    mark_notified(event)
    told.size
  end

  # After reopen!: every active linked guest hears once that the set time is
  # withdrawn, the organizer (who pressed the button) not at all. Never
  # capped: reopen! itself allows at most two per event. The withdrawn
  # window travels in the params so the job prints it and builds the
  # cancelled calendar file without reading the row. Returns the number told.
  def reopened!(event:, previous_window:)
    event.ensure_not_cancelled!
    told = event.guests.active.linked.to_a
    told.each do |guest|
      mail!(:reopened, event:, to: guest, token: link_token!(guest), sender: event.organizer, previous_window:, sequence: event.revision)
    end
    mark_notified(event)
    told.size
  end

  private

  def notice_recipients(event, reason)
    recipients = event.guests.active.linked
    return recipients unless reason == :offer

    recipients = recipients.where.not(responded_at: nil)
    event.offer_revision_added.zero? ? recipients.where(declined_at: nil) : recipients
  end

  # The claim rule for a mail's link: a fresh pending token for an unclaimed
  # guest, which retires the previous pending one and leaves the live link
  # working; none for a claimed guest, whom the mailer links to the
  # signed-in page, nor for the organizer, whose copy carries no link.
  def link_token!(participant)
    participant.issue_pending_token! if participant.guest? && !participant.claimed?
  end

  # The ledger row first, then the job; the rest of the params ride along.
  def mail!(kind, event:, to:, token: nil, sender: nil, request_ip: nil, **params)
    delivery = MailDelivery.create!(event:, participant: to, kind:, recipient_email: to.email, sender_email: sender&.email, request_ip:)
    ParticipantMailer.with(delivery:, token:, **params).public_send(kind).deliver_later
  end

  # Monotonic: a batch enqueued from an older page must never lower the mark
  # and make "Tell the guests" reappear for changes everyone already heard.
  def mark_notified(event)
    Event.where(id: event.id).where(notified_revision: ...event.revision).update_all(notified_revision: event.revision)
    event.notified_revision = [ event.notified_revision, event.revision ].max
  end
end
