class EventsController < ApplicationController

  def create
    @event = Event.new(list_params)
    @event.user = current_user
    @event.save
  end

  def new
    @event = Event.new
  end

  private

  def event_params
    params.require(:event).permit(:name)
  end
end
