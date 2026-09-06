# Preview all emails at http://localhost:3000/rails/mailers/participant_mailer
class ParticipantMailerPreview < ActionMailer::Preview
  def organizer_link
    ParticipantMailer.with(delivery: sample(:organizer_link, organizer: true), token: sample_token).organizer_link
  end

  def invitation
    ParticipantMailer.with(delivery: sample(:invitation), token: sample_token).invitation
  end

  def response_confirmation
    ParticipantMailer.with(delivery: sample(:response_confirmation), token: nil).response_confirmation
  end

  # The guest copy: a link by the claim rule and the calendar file.
  def finalized
    ParticipantMailer.with(delivery: sample(:finalized), token: sample_token, window: sample_window).finalized
  end

  # The organizer's receipt: no link.
  def finalized_organizer_copy
    ParticipantMailer.with(delivery: sample(:finalized, organizer: true), token: nil, window: sample_window).finalized
  end

  # One change notice per reason: the details form (with a rename), the
  # offer form and the Tell the guests button.
  def event_updated_details
    event = sample_event
    changes = { "name" => [ "Film night", event.name ], "place" => [ nil, event.place ] }
    ParticipantMailer.with(delivery: sample(:event_updated), token: sample_token, reason: :details, changes: changes).event_updated
  end

  def event_updated_offer
    ParticipantMailer.with(delivery: sample(:event_updated), token: sample_token, reason: :offer, changes: nil).event_updated
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

  private

  def sample_event
    Event.includes(:participants, :activities).order(:id).first or raise "seed an event first"
  end

  def sample(kind, organizer: false)
    event = sample_event
    participant = organizer ? event.organizer : (event.guests.first || event.organizer)
    MailDelivery.new(event: event, participant: participant, kind: kind, recipient_email: participant.email)
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
