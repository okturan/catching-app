# Every transactional mail. Parameters: delivery (the MailDelivery ledger
# row, which carries event, participant and recipient), token (the raw
# capability token for the templates that carry a link) and, for finalized
# and cancelled, window (the set start and end, or nil for a pending cancel).
class ParticipantMailer < ApplicationMailer
  helper MailTextHelper
  include MailTextHelper
  include EventsHelper

  CALENDAR_ATTACHMENT = "catching-app.ics".freeze
  CALENDAR_MIME_TYPE = "text/calendar; method=PUBLISH".freeze

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

  # The set time and what a guest asks next: where, how long, the plan with
  # derived starts, a link (guests only, by the claim rule) and the calendar
  # file. The window comes from the params, never from the row, so a job
  # that runs after a reopen still prints and attaches what was set.
  def finalized
    start_time, end_time = params.fetch(:window)
    zone = @participant&.time_zone.presence || @event.time_zone
    @recipient_window = window_in(zone, start_time, end_time)
    @event_window = window_in(@event.time_zone, start_time, end_time)
    @place = mail_safe(@event.place).presence
    @duration = @event.duration_minutes && duration_label(@event.duration_minutes)
    @plan = plan_lines(start_time, zone)
    @link = guest_link
    attach_calendar(window: [ start_time, end_time ], status: :confirmed)
    date = start_time.in_time_zone(zone_named(zone)).strftime("%a %-d %b")
    mail(
      to: @delivery.recipient_email,
      reply_to: @event.organizer&.email,
      subject: subject_for("#{mail_safe(@event.name)} is set for #{date}")
    )
  end

  # No link and no promise of more mail. The window comes from the params,
  # so a job that runs after the row changed still prints what was set.
  def cancelled
    @organizer = @event.organizer
    start_time, end_time = params[:window]
    if start_time && end_time
      zone = @participant&.time_zone.presence || @event.time_zone
      @recipient_window = window_in(zone, start_time, end_time)
      @event_window = window_in(@event.time_zone, start_time, end_time)
    end
    mail(
      to: @delivery.recipient_email,
      reply_to: @organizer&.email,
      subject: subject_for("#{mail_safe(@event.name)} is cancelled")
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

  # Guests get a link by the claim rule: the pending token issued for this
  # mail for an unclaimed guest, the signed-in page for a claimed one. The
  # organizer's copy carries none.
  def guest_link
    return nil if @participant.nil? || @participant.organizer?
    return my_participation_url(@participant) if @participant.claimed?

    params[:token] && participation_url(params[:token])
  end

  # "Pizza (30 min) at 20:00 (Asia/Kolkata), 15:30 (Europe/Berlin)": each
  # item with its derived start in the recipient zone, then the event zone
  # when that differs. Names pass through mail_safe; descriptions stay home.
  def plan_lines(start_time, zone)
    both_zones = zone_named(zone).name != zone_named(@event.time_zone).name
    @event.plan_timeline(from: start_time).map do |activity, start|
      line = mail_safe(activity.name)
      line += " (#{duration_label(activity.duration)})" if activity.duration
      next line unless start

      line += " at #{clock_in(zone, start)}"
      line += ", #{clock_in(@event.time_zone, start)}" if both_zones
      line
    end
  end

  def attach_calendar(window:, status:)
    attachments[CALENDAR_ATTACHMENT] = {
      mime_type: CALENDAR_MIME_TYPE,
      content: CalendarFile.new(@event, mode: :mail, window: window, status: status).body
    }
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
