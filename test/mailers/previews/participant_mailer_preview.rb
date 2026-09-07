# Preview all emails at http://localhost:3000/rails/mailers/participant_mailer
#
# Every sample reads the first event in the database and fills, in memory
# only, what that event lacks: a place, a planned length, a two-item plan and
# a guest in another zone, so every line of every template shows. Nothing is
# saved: the ledger rows are never persisted and the event is never written.
class ParticipantMailerPreview < ActionMailer::Preview
  def organizer_link
    ParticipantMailer.with(delivery: sample(:organizer_link, participant: sample_organizer), token: sample_token).organizer_link
  end

  def invitation
    ParticipantMailer.with(delivery: sample(:invitation), token: sample_token).invitation
  end

  def response_confirmation
    ParticipantMailer.with(delivery: sample(:response_confirmation), token: nil).response_confirmation
  end

  # The guest copy: the facts, the plan with derived starts in both zones, a
  # link by the claim rule and the calendar file.
  def finalized
    ParticipantMailer.with(delivery: sample(:finalized), token: sample_token, window: sample_window).finalized
  end

  # The organizer's receipt: no link, no Leave sentence.
  def finalized_organizer_copy
    ParticipantMailer.with(delivery: sample(:finalized, participant: sample_organizer), token: nil, window: sample_window).finalized
  end

  # One change notice per reason: the details form (with a rename), the
  # offer form and the Tell the guests button.
  def event_updated_details
    event = sample_event
    changes = { "name" => [ "Film night", event.name ], "place" => [ nil, event.place ] }
    ParticipantMailer.with(delivery: sample(:event_updated), token: sample_token, reason: :details, changes: changes).event_updated
  end

  # A guest who replied before the offer changed: some picks still stand.
  def event_updated_offer
    guest = sample_guest
    guest.responded_at ||= 2.days.ago
    event = sample_event
    event.offer_revised_at = guest.responded_at + 1.hour
    event.offer_revision_added = 2
    event.offer_revision_removed = 1
    ParticipantMailer.with(delivery: sample(:event_updated, participant: guest), token: sample_token, reason: :offer, changes: nil).event_updated
  end

  # A guest whose every pick was removed: the reply is voided, please pick again.
  def event_updated_offer_voided
    guest = sample_guest
    guest.responded_at ||= 2.days.ago
    guest.reply_voided_at = Time.current
    ParticipantMailer.with(delivery: sample(:event_updated, participant: guest), token: sample_token, reason: :offer, changes: nil).event_updated
  end

  def event_updated_all
    ParticipantMailer.with(delivery: sample(:event_updated), token: sample_token, reason: :all, changes: nil).event_updated
  end

  # A cancel after the time was set: the file withdraws the calendar entry.
  def cancelled
    ParticipantMailer.with(delivery: sample(:cancelled), token: nil, window: sample_window).cancelled
  end

  def cancelled_while_pending
    ParticipantMailer.with(delivery: sample(:cancelled), token: nil, window: nil).cancelled
  end

  # The set time withdrawn: the window it was, the link and the file that
  # clears the calendar entry.
  def reopened
    ParticipantMailer.with(delivery: sample(:reopened), token: sample_token, previous_window: sample_window).reopened
  end

  private

  # The first event, with a place, a planned length and a plan filled in
  # memory when it has none.
  def sample_event
    @sample_event ||= begin
      event = Event.includes(:activities).order(:id).first or raise "seed an event first"
      event.place = "Ege's place" if event.place.blank?
      event.duration_minutes ||= 150
      if event.activities.empty?
        event.activities.build(name: "Pizza first", duration: 30, position: 0)
        event.activities.build(name: "The movie", duration: 120, position: 1)
      end
      event
    end
  end

  def sample_organizer
    sample_event.organizer or raise "the sample event has no organizer"
  end

  # The first active guest, or an unclaimed one built for the preview; either
  # way in another zone than the event so both zones print.
  def sample_guest
    @sample_guest ||= begin
      guest = sample_event.guests.active.order(:id).first ||
        sample_event.participants.build(role: :guest, email: "guest@example.test", name: "Sedef")
      if guest.time_zone.blank? || guest.time_zone == sample_event.time_zone
        guest.time_zone = sample_event.time_zone == "Asia/Kolkata" ? "Europe/Berlin" : "Asia/Kolkata"
      end
      guest
    end
  end

  # An unsaved ledger row: the mailer reads event, participant and recipient
  # from it and skips the delivered stamp because it is not persisted.
  def sample(kind, participant: sample_guest)
    MailDelivery.new(event: sample_event, participant: participant, kind: kind, recipient_email: participant.email)
  end

  # The set window when the sample event has one, otherwise a plausible one.
  def sample_window
    event = sample_event
    start_time = event.start_time || 1.week.from_now.utc.change(hour: 18)
    [ start_time, event.end_time || start_time + 2.hours ]
  end

  def sample_token
    "previewtoken" + "0" * 20
  end
end
