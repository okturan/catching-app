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

  def finalized
    ParticipantMailer.with(delivery: sample(:finalized), token: nil).finalized
  end

  private

  def sample(kind, organizer: false)
    event = Event.includes(:participants).order(:id).first or raise "seed an event first"
    participant = organizer ? event.organizer : (event.guests.first || event.organizer)
    MailDelivery.new(event: event, participant: participant, kind: kind, recipient_email: participant.email)
  end

  def sample_token
    "previewtoken" + "0" * 20
  end
end
