class EventsController < ApplicationController
  include TimeSlotParams

  def new
    @event = Event.new(slot_minutes: 30)
  end

  def create
    organizer = { email: current_user.email, name: current_user.full_name, user: current_user }
    invitees = InviteeListParser.call(params.dig(:invitations, :emails), organizer_email: current_user.email)
    slot_minutes = Event::SLOT_MINUTES.include?(event_params[:slot_minutes].to_i) ? event_params[:slot_minutes].to_i : 30

    @event = Event.plan!(
      attributes: event_params,
      organizer: organizer,
      starts_at: parsed_time_slots(slot_minutes: slot_minutes),
      invitee_emails: invitees
    )
    organizer_row = @event.organizer
    organizer_row.update_columns(link_opened_at: Time.current)
    organizer_row.issue_live_token!

    redirect_to my_participation_path(organizer_row), notice: "Event created."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @event ||= Event.new(event_params)
    @event.errors.add(:base, error.message) if @event.errors.empty?
    render :new, status: :unprocessable_entity
  end

  def pending
    @organizer_email = flash[:organizer_email]
  end

  private

  def event_params
    params.require(:event).permit(:name, :description, :slot_minutes, :time_zone)
  end
end
