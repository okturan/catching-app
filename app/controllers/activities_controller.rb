class ActivitiesController < ApplicationController
  before_action :set_accessible_event, only: %i[index show]
  before_action :set_owned_event, only: %i[new create]
  before_action :set_participation
  before_action :set_activity, only: :show

  def index
    @activities = @event.activities.order(created_at: :desc)
  end

  def show; end

  def new
    @activity = @event.activities.build
  end

  def create
    @activity = @event.activities.build(activity_params)

    if @activity.save
      redirect_to event_activity_path(@event, @activity), notice: "Activity added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_accessible_event
    @event = Event.for_user(current_user).find(params[:event_id])
  end

  def set_owned_event
    @event = Event.organized_by(current_user).find(params[:event_id])
  end

  def set_participation
    @participation = current_user.participants.active.find_by!(event_id: @event.id)
  end

  def set_activity
    @activity = @event.activities.find(params[:id])
  end

  def activity_params
    params.require(:activity).permit(:name, :description, :duration)
  end
end
