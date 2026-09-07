class EventsController < ApplicationController
  include TimeSlotParams

  skip_before_action :authenticate_user!, only: %i[new create pending]

  # Courtesy layer only: the load-bearing limits are the ledger caps.
  rate_limit to: 5, within: 10.minutes, only: :create

  def new
    # No zone: the column default (UTC) would out-rank the browser zone in
    # populateTimeZoneSelect and paint every visitor the wrong hours.
    @event = Event.new(slot_minutes: 30, time_zone: nil)
    @organizer = organizer_attributes
    @organizer_errors = {}
  end

  # Anyone with an email address can plan. Nothing is sent to guests until
  # the organizer opens the emailed link (verify-by-click).
  def create
    @organizer = organizer_attributes
    invitees = InviteeListParser.call(params.dig(:invitations, :emails), organizer_email: @organizer[:email])
    MailDelivery::Caps.check_event_creation!(organizer_email: @organizer[:email], request_ip: request.remote_ip)

    @event = Event.plan!(
      attributes: event_params,
      organizer: @organizer.merge(user: current_user),
      starts_at: parsed_time_slots(slot_minutes: requested_slot_minutes),
      invitee_emails: invitees
    )
    Deliveries.organizer_link!(event: @event, organizer: @event.organizer, request_ip: request.remote_ip)

    flash[:organizer_email] = @organizer[:email]
    redirect_to pending_events_path, notice: "Event created."
  rescue MailDelivery::CapExceeded => error
    redirect_to new_event_path, alert: error.message, status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    # Re-validating reproduces the record's own errors, so appending the
    # message would print each one twice: once in the summary, once under
    # the field. The organizer's errors have no record on this page, so they
    # are carried across by hand.
    render_form_again(record: error.record)
  rescue ArgumentError => error
    render_form_again(base: error.message)
  end

  def pending
    @organizer_email = flash[:organizer_email]
  end

  private

  def render_form_again(record: nil, base: nil)
    @event = Event.new(event_params)
    @event.validate
    @event.errors.add(:base, base) if base
    @organizer_errors = record.is_a?(Participant) ? organizer_error_messages(record) : {}
    render :new, status: :unprocessable_entity
  end

  def organizer_error_messages(record)
    { name: record.errors[:name].first, email: record.errors[:email].first }.compact
  end

  def event_params
    params.fetch(:event, {}).permit(:name, :description, :slot_minutes, :time_zone, :place, :place_url, :duration_minutes)
  end

  def requested_slot_minutes
    requested = event_params[:slot_minutes].to_i
    Event::SLOT_MINUTES.include?(requested) ? requested : 30
  end

  # Signed in, the organizer is the account; a posted organizer[email] is ignored.
  def organizer_attributes
    if user_signed_in?
      { email: current_user.email, name: current_user.full_name }
    else
      posted = params.fetch(:organizer, {}).permit(:name, :email)
      { email: posted[:email].to_s.strip.downcase, name: posted[:name].to_s.squish }
    end
  end
end
