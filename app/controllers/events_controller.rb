class EventsController < ApplicationController
  include TimeSlotParams

  skip_before_action :authenticate_user!, only: %i[new create pending]

  # Courtesy layer only: the load-bearing limits are the ledger caps.
  rate_limit to: 5, within: 10.minutes, only: :create

  def new
    @event = Event.new(slot_minutes: 30)
    @organizer = organizer_attributes
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
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @event = Event.new(event_params)
    @event.validate
    @event.errors.add(:base, error.message)
    render :new, status: :unprocessable_entity
  end

  def pending
    @organizer_email = flash[:organizer_email]
  end

  private

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
