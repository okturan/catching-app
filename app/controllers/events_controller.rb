class EventsController < ApplicationController
  before_action :set_accessible_event, only: :show
  before_action :set_owned_event, only: :update

  def show
    @host = @event.user
    @host_time_slots = @event.time_slots.where(user: @host).order(:start_time)
    @my_time_slots = @event.time_slots.where(user: current_user).order(:start_time)
    @availability_counts = @event.time_slots.where.not(user: current_user).group(:start_time).count.transform_keys(&:iso8601)
    @guests = @event.invited_users.order(:first_name, :last_name)
  end

  def new
    @event = current_user.events.build
    load_invitees
  end

  def create
    @event = current_user.events.build(event_params)

    Event.transaction do
      @event.save!
      @event.replace_time_slots!(user: current_user, starts_at: parsed_time_slots)
      @event.invited_users = permitted_invitees
    end

    redirect_to @event, notice: "Event created."
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @event.errors.add(:base, error.message) if @event.errors.empty?
    load_invitees
    render :new, status: :unprocessable_entity
  end

  def update
    @event.finalize!(starts_at: parsed_time_slots)

    redirect_to @event, notice: "Meeting time confirmed."
  rescue ActiveRecord::RecordInvalid, ArgumentError, Event::ClosedError => error
    redirect_to @event, alert: error.message, status: :see_other
  end

  private

  def set_accessible_event
    @event = Event.accessible_to(current_user).find(params[:id])
  end

  def set_owned_event
    @event = current_user.events.find(params[:id])
  end

  def load_invitees
    @users = User.where.not(id: current_user.id).order(:first_name, :last_name)
  end

  def permitted_invitees
    ids = Array(params.dig(:event, :invited_user_ids)).compact_blank
    User.where(id: ids).where.not(id: current_user.id)
  end

  def event_params
    params.require(:event).permit(:name, :description)
  end

  def parsed_time_slots
    TimeSlotParser.call(params.require(:time_slots).fetch(:time_slot_array))
  rescue KeyError, TypeError
    raise ActionController::ParameterMissing, :time_slots
  end
end
