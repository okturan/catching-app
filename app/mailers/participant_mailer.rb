# Every transactional mail. Parameters: delivery (the MailDelivery ledger
# row, which carries event, participant and recipient) and token (the raw
# capability token for the two templates that carry a link).
class ParticipantMailer < ApplicationMailer
  helper MailTextHelper
  include MailTextHelper

  SUBJECT_PREFIX = "Catching App: ".freeze
  SUBJECT_LIMIT = 80

  before_action :load_delivery
  after_deliver :mark_delivered

  def organizer_link
    @link = participation_url(params.fetch(:token))
    mail(to: @delivery.recipient_email, subject: "#{SUBJECT_PREFIX}your organizer link")
  end

  def invitation
    @organizer = @event.organizer
    @link = participation_url(params.fetch(:token))
    @offer = offer_summary
    mail(
      to: @delivery.recipient_email,
      reply_to: @organizer.email,
      subject: subject_for("#{mail_safe(@organizer.name)} invited you to #{mail_safe(@event.name)}")
    )
  end

  def response_confirmation
    zone = @participant&.time_zone.presence || @event.time_zone
    instants = @event.time_slots.where(participant_id: @participant.id).order(:start_time).pluck(:start_time)
    @declined = instants.empty?
    @recipient_ranges = coalesced_ranges(instants, @event.slot_minutes, zone)
    @event_ranges = coalesced_ranges(instants, @event.slot_minutes, @event.time_zone)
    mail(to: @delivery.recipient_email, subject: subject_for("your reply to #{mail_safe(@event.name)} is saved"))
  end

  def finalized
    zone = @participant&.time_zone.presence || @event.time_zone
    @recipient_window = window_in(zone, @event.start_time, @event.end_time)
    @event_window = window_in(@event.time_zone, @event.start_time, @event.end_time)
    date = @event.start_time.in_time_zone(zone_named(zone)).strftime("%a %-d %b")
    mail(
      to: @delivery.recipient_email,
      reply_to: @event.organizer&.email,
      subject: subject_for("#{mail_safe(@event.name)} is set for #{date}")
    )
  end

  private

  def load_delivery
    @delivery = params.fetch(:delivery)
    @event = @delivery.event
    @participant = @delivery.participant
  end

  def mark_delivered
    @delivery.update_columns(delivered_at: Time.current) if @delivery.persisted?
  end

  def subject_for(text)
    "#{SUBJECT_PREFIX}#{text}".squish.truncate(SUBJECT_LIMIT)
  end

  def offer_summary
    offered = @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
    return nil if offered.empty?

    zone = zone_named(@event.time_zone)
    first = offered.first.in_time_zone(zone).strftime("%-d %b")
    last = offered.last.in_time_zone(zone).strftime("%-d %b %Y")
    "#{@event.slot_minutes}-minute slots between #{first} and #{last} (#{zone.name})"
  end
end
