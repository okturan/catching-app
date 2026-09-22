# The mails that go to everyone on an event at once: the set time, a change
# notice, the withdrawn time and the cancellation. Each marks the guests told
# about the revision it describes, and only the cancellation still goes out
# once the event is cancelled.
module Event::Announcements
  extend ActiveSupport::Concern

  # How far a change notice reached, in the words the organizer reads.
  NoticeReport = Data.define(:sent, :skipped) do
    def reached_anyone? = (sent + skipped).positive?

    def to_s
      [ "#{sent} #{"guest".pluralize(sent)} emailed.",
        ("#{skipped} skipped (recently notified). Try again after 10 minutes." if skipped.positive?) ].compact.join(" ")
    end
  end

  # After finalize!: everyone active with a link, the organizer included as
  # a receipt, never capped. The set window travels in the params so a
  # retried job never reads the row.
  def announce_finalization!
    ensure_not_cancelled!
    window = [ start_time, end_time ]
    participants.active.linked.each do |participant|
      MailDelivery.deliver_later(:finalized, to: participant, token: participant.mail_link_token!, window:, sequence: revision)
    end
    mark_notified!
  end

  # One coalesced change notice, only when the organizer asks (the details
  # checkbox, the offer checkbox or Tell the guests). Recipients are active
  # linked guests; an offer notice goes only to guests who already replied,
  # and skips declined guests when nothing was added. A recipient over the
  # notice caps is skipped and counted. The organizer never receives one.
  def notify_guests!(reason:, by:, request_ip:, changes: nil)
    ensure_not_cancelled!
    raise Refusal, "Open your organizer link before emailing guests" unless by.link_opened_at?

    sent = skipped = 0
    notice_recipients(reason).each do |guest|
      MailDelivery::Caps.check_update_notice!(event: self, organizer: by, recipient_email: guest.email, request_ip:)
    rescue MailDelivery::CapExceeded
      skipped += 1
    else
      MailDelivery.deliver_later(:event_updated, to: guest, token: guest.mail_link_token!, sender: by, request_ip:, reason:, changes:)
      sent += 1
    end
    mark_notified! if sent.positive?
    NoticeReport.new(sent:, skipped:)
  end

  # After reopen!: every active linked guest hears once that the set time is
  # withdrawn, the organizer (who pressed the button) not at all. Never
  # capped: reopen! itself allows at most two per event. The withdrawn window
  # travels in the params so the job prints it and builds the cancelled
  # calendar file without reading the row. Returns the number told.
  def announce_reopening!(previous_window)
    ensure_not_cancelled!
    told = guests.active.linked.to_a
    told.each do |guest|
      MailDelivery.deliver_later(:reopened, to: guest, token: guest.mail_link_token!, sender: organizer, previous_window:, sequence: revision)
    end
    mark_notified!
    told.size
  end

  # The one last mail: everyone active with a link, declined guests and the
  # organizer included, left and never-invited excluded. No token, no link,
  # no cap. The set window, when there was one, travels in the params so a
  # retried job never reads the live row. Returns the number of people told.
  def announce_cancellation!
    window = [ start_time, end_time ] if finalized?
    told = participants.active.linked.to_a
    told.each { MailDelivery.deliver_later(:cancelled, to: it, sender: organizer, window:, sequence: revision) }
    mark_notified!
    told.size
  end

  # Monotonic: a batch enqueued from an older page must never lower the mark
  # and make "Tell the guests" reappear for changes everyone already heard.
  def mark_notified!
    Event.where(id:).where(notified_revision: ...revision).update_all(notified_revision: revision)
    self.notified_revision = [ notified_revision, revision ].max
  end

  private

  def notice_recipients(reason)
    recipients = guests.active.linked
    return recipients unless reason == :offer

    recipients = recipients.where.not(responded_at: nil)
    offer_revision_added.zero? ? recipients.where(declined_at: nil) : recipients
  end
end
