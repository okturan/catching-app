# Every transactional mail. Parameters: delivery (the MailDelivery ledger
# row, which carries event, participant and recipient), token (the raw
# capability token for the templates that carry a link), for finalized and
# cancelled, window (the set start and end, or nil for a pending cancel),
# and for reopened, previous_window (the withdrawn start and end).
class ParticipantMailer < ApplicationMailer
  helper MailTextHelper
  include MailTextHelper

  self.delivery_job = MailDeliveryJob

  CALENDAR_ATTACHMENT = "catching-app.ics".freeze
  CALENDAR_MIME_TYPE = "text/calendar; method=PUBLISH".freeze

  SUBJECT_PREFIX = "Catching App: ".freeze
  SUBJECT_LIMIT = 80

  default to: -> { @delivery.recipient_email }

  before_action :load_delivery
  after_deliver :mark_delivered

  def organizer_link
    @link = participant_url(params.fetch(:token))
    mail(subject: "#{SUBJECT_PREFIX}your organizer link")
  end

  def invitation
    @link = participant_url(params.fetch(:token))
    @offer = offer_summary
    mail(reply_to: @organizer.email, subject: subject_for("#{mail_safe(@organizer.name)} invited you to #{mail_safe(@event.name)}"))
  end

  def response_confirmation
    instants = @participant.available_start_times
    @declined = instants.empty?
    @recipient_ranges = coalesced_ranges(instants, @event.slot_minutes, recipient_zone)
    @event_ranges = coalesced_ranges(instants, @event.slot_minutes, @event.time_zone)
    mail(subject: subject_for("your reply to #{mail_safe(@event.name)} is saved"))
  end

  # The set time and what a guest asks next: where, how long, the plan with
  # derived starts, a link (guests only, by the claim rule) and the calendar
  # file. The window comes from the params, never from the row, so a job
  # that runs after a reopen still prints and attaches what was set.
  def finalized
    window = params.fetch(:window)
    describe_window(*window)
    @place = mail_safe(@event.place).presence
    @duration = @event.planned_length
    @plan = plan_lines(window.first)
    @link = guest_link
    attach_calendar(window:, status: :confirmed)
    mail(reply_to: @organizer.email, subject: subject_for("#{mail_safe(@event.name)} is set for #{recipient_day(window.first)}"))
  end

  # One coalesced notice: why it was sent, what is true now and, for an
  # offer change, where the recipient's own picks stand. Guests only, the
  # link by the claim rule. The body reads the current row on purpose: a
  # notice describes the event as it is when the job runs.
  def event_updated
    @reason = params.fetch(:reason)
    @changes = params[:changes].to_h
    @renamed = @changes["name"]
    @place = mail_safe(@event.place).presence
    @duration = @event.planned_length
    @plan = @event.plan_items.map { plan_item_line(it) }
    @situation = offer_situation if @reason == :offer
    @reason_line = reason_line
    @link = guest_link
    mail(reply_to: @organizer.email, subject: subject_for("#{mail_safe(@organizer.name)} changed #{mail_safe(@event.name)}"))
  end

  # No link and no promise of more mail. The window comes from the params,
  # so a job that runs after the row changed still prints what was set; when
  # there was one, the attached file withdraws the calendar entry.
  def cancelled
    if (window = params[:window])
      describe_window(*window)
      attach_calendar(window:, status: :cancelled)
    end
    mail(reply_to: @organizer.email, subject: subject_for("#{mail_safe(@event.name)} is cancelled"))
  end

  # The set time is withdrawn: the window in both zones, the promise that
  # the guest's paint still counts, the link by the claim rule and a file
  # that clears the calendar entry. Guests only. The window comes from the
  # params, never from the row, which is already pending again.
  def reopened
    window = params.fetch(:previous_window)
    describe_window(*window)
    @link = guest_link
    attach_calendar(window:, status: :cancelled)
    mail(reply_to: @organizer.email, subject: subject_for("#{mail_safe(@event.name)} is no longer set for #{recipient_day(window.first)}"))
  end

  private

  def load_delivery
    @delivery = params.fetch(:delivery)
    @event = @delivery.event
    @participant = @delivery.participant
    @organizer = @event.organizer
  end

  def mark_delivered
    @delivery.update_columns(delivered_at: Time.current)
  end

  def subject_for(text)
    "#{SUBJECT_PREFIX}#{text}".squish.truncate(SUBJECT_LIMIT)
  end

  # Times read in the recipient's own zone once they have chosen one.
  def recipient_zone
    @participant.time_zone || @event.time_zone
  end

  def recipient_day(instant)
    instant.in_time_zone(recipient_zone).to_fs(:day)
  end

  # The templates print the event's zone only when it reads differently.
  def describe_window(start_time, end_time)
    @recipient_window = window_in(recipient_zone, start_time, end_time)
    @event_window = window_in(@event.time_zone, start_time, end_time)
  end

  # Guests get a link by the claim rule: the pending token issued for this
  # mail for an unclaimed guest, the signed-in page for a claimed one. The
  # organizer's copy carries none, and so does the mail of a guest who lost
  # the claim after it was queued without a token.
  def guest_link
    return if @participant.organizer?
    return participant_url(@participant) if @participant.claimed?

    participant_url(params[:token]) if params[:token]
  end

  # "Pizza (30 min) at 20:00 (Asia/Kolkata), 15:30 (Europe/Berlin)": each
  # item with its derived start in the recipient zone, then the event zone
  # when that differs. Names pass through mail_safe; descriptions stay home.
  def plan_lines(start_time)
    both_zones = recipient_zone != @event.time_zone
    @event.plan_timeline(from: start_time).map do |item, start|
      line = plan_item_line(item)
      next line unless start

      line += " at #{clock_in(recipient_zone, start)}"
      line += ", #{clock_in(@event.time_zone, start)}" if both_zones
      line
    end
  end

  # "Pizza (30 min)": the name through mail_safe and the length, never the
  # description.
  def plan_item_line(item)
    line = mail_safe(item.name)
    line += " (#{item.length})" if item.length
    line
  end

  # The recipient's own situation after an offer change, read from the row
  # at send time: a voided guest has nothing left, a guest who replied
  # before the change still holds some picks, a declined guest hears that
  # times were added (removal-only revisions never reach them).
  def offer_situation
    if @participant.voided?
      "None of the times you picked are offered any more. Please pick again."
    elsif @participant.declined_at?
      "You said none of the times worked. New times were added."
    elsif @participant.replied_before_revision?
      "Some of the offered times changed (#{@event.offer_revision_added} added, #{@event.offer_revision_removed} removed). " \
        "Your remaining picks still stand; look again."
    end
  end

  # The one reason line at the top of a notice.
  def reason_line
    organizer = mail_safe(@organizer.name)
    event = mail_safe(@event.name)
    case @reason
    when :details then "#{organizer} changed the details of #{event}."
    when :offer then "#{organizer} changed the offered times for #{event}."
    else "#{organizer} changed #{event}. Here is what is set now."
    end
  end

  # The sequence travels with the window: a job delayed past a reopen or a
  # cancel must publish the revision it was enqueued at, never a newer one.
  def attach_calendar(window:, status:)
    attachments[CALENDAR_ATTACHMENT] = {
      mime_type: CALENDAR_MIME_TYPE,
      content: CalendarFile.new(@event, mode: :mail, window:, status:, sequence: params[:sequence]).body
    }
  end

  # "60-minute slots between 15 Jan and 20 Jan 2030 (Europe/Berlin)"
  def offer_summary
    offer = @organizer.time_slots
    first = offer.minimum(:start_time).in_time_zone(@event.time_zone)
    last = offer.maximum(:start_time).in_time_zone(@event.time_zone)
    "#{@event.slot_minutes}-minute slots between #{first.strftime("%-d %b")} and #{last.strftime("%-d %b %Y")} (#{@event.time_zone})"
  end
end
