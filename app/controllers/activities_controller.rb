class ActivitiesController < ApplicationController
  def new
    @activity = Activity.new
  end

  def create
    @activity = Activity.new(activity_params)
    @activity.event = current_event
    @activity.save
  end

  def edit
  end

  def show
  end

  def index
    @activities = Activity.all
  end

  def destroy
    @activity = Activity.find(params[:id])
    @activity.destroy
  end

  private

  def activity_params
    params.require(:activity).permit(:name, :activity_type, :start_time, :end_time)
  end
end
