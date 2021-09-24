class EventsController < ApplicationController
  def create
    # Create new event with only event_params
    @event = Event.new(event_params)
    @event.user = current_user
    @event.save!

    # Create timeslots with time_slot_array_params and with the event created above
    @time_slot_array = time_slot_array_params[:time_slot_array]
    @time_slots = @time_slot_array.split(',')
    @time_slots.each do |slot|
      time_slot = TimeSlot.new(start_time: slot, user: current_user, event: @event)
      time_slot.save!
    end

    Invitation.create!(event: @event, user_id: user_info_params[:user_id])

    redirect_to dashboard_path
  end

  def new
    @users = User.all
    @event = Event.new
  end

  private

  def event_params
    params.require(:event).permit(:name, :description)
  end

  def time_slot_array_params
    params.require(:time_slots).permit(:time_slot_array)
  end

  def user_info_params
    params.require(:user_info).permit(:user_id)
  end
end
