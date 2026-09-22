class EventsController < ApplicationController
  include TimeSlotParams

  allow_unauthenticated_access only: %i[new create pending]

  # A courtesy layer only; the ledger caps are what hold.
  rate_limit to: 5, within: 10.minutes, only: :create

  def new
    # No zone yet: the column's UTC default would win over the browser's own
    # zone in the picker and paint every visitor the wrong hours.
    @event = Event.new(time_zone: nil)
    @organizer = Participant.organizer.new(organizer_attributes)
  end

  # Anyone with an email address can plan. Nothing goes to guests until the
  # organizer opens the emailed link.
  def create
    @organizer = Participant.organizer.new(organizer_attributes)
    MailDelivery::Caps.check_event_creation!(organizer_email: @organizer.email, request_ip: request.remote_ip)

    @event = Event.plan!(attributes: event_params, organizer: { name: @organizer.name, email: @organizer.email, user: Current.user },
      starts_at: parsed_time_slots(slot_minutes: requested_slot_minutes))
    @event.organizer.send_organizer_link!(request_ip: request.remote_ip)

    flash[:organizer_email] = @organizer.email
    redirect_to pending_events_path, notice: "Event created.", status: :see_other
  rescue MailDelivery::CapExceeded => refusal
    redirect_to new_event_path, alert: refusal.message, status: :see_other
  rescue ActiveRecord::RecordInvalid
    render_form_again
  rescue Refusal => refusal
    render_form_again(base: refusal.message)
  end

  def pending
    @organizer_email = flash[:organizer_email]
  end

  private

  # Every mistake at once: the event and its organizer are validated afresh,
  # and a refusal about the grid joins them as the event's base error.
  def render_form_again(base: nil)
    @event = Event.new(event_params)
    @event.validate
    @event.errors.add(:base, base) if base
    @organizer = @event.participants.organizer.new(organizer_attributes)
    @organizer.validate
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
    if authenticated?
      { email: Current.user.email, name: Current.user.full_name }
    else
      params.fetch(:organizer, {}).permit(:name, :email)
    end
  end
end
