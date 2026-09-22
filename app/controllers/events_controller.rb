class EventsController < ApplicationController
  include TimeSlotParams

  skip_before_action :authenticate_user!, only: %i[new create pending]

  # A courtesy layer only; the ledger caps are what hold.
  rate_limit to: 5, within: 10.minutes, only: :create

  def new
    # No zone yet: the column's UTC default would win over the browser's own
    # zone in the picker and paint every visitor the wrong hours.
    @event = Event.new(time_zone: nil)
    @organizer = organizer_attributes
    @organizer_errors = {}
  end

  # Anyone with an email address can plan. Nothing goes to guests until the
  # organizer opens the emailed link.
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
  rescue MailDelivery::CapExceeded => refusal
    redirect_to new_event_path, alert: refusal.message, status: :see_other
  rescue ActiveRecord::RecordInvalid => invalid
    # Re-validating the event reproduces its own errors; the organizer's
    # have no record on this page, so they are carried across by hand.
    render_form_again(organizer: invalid.record.is_a?(Participant) ? invalid.record : nil)
  rescue Refusal => refusal
    render_form_again(base: refusal.message)
  end

  def pending
    @organizer_email = flash[:organizer_email]
  end

  private

  def render_form_again(organizer: nil, base: nil)
    @event = Event.new(event_params)
    @event.validate
    @event.errors.add(:base, base) if base
    @organizer_errors = organizer ? { name: organizer.errors[:name].first, email: organizer.errors[:email].first }.compact : {}
    render :new, status: :unprocessable_entity
  end

  def event_params
    params.expect(event: %i[name description slot_minutes time_zone place place_url duration_minutes])
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
      { email: Participant.normalize_value_for(:email, posted[:email].to_s), name: Participant.normalize_value_for(:name, posted[:name].to_s) }
    end
  end
end
