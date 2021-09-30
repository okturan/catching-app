class TimeSlotsController < ApplicationController
  def create
    @time_slot_array = my_params[:time_slot_array]
    @event = Event.find(my_params[:event_id])
    @time_slots = @time_slot_array.split(',')
    @time_slots.each do |slot|
      time_slot = TimeSlot.new(start_time: slot, user: current_user, event: @event)
      time_slot.save!
    end

    redirect_to dashboard_path
  end

  private

  def my_params
    params.require(:time_slots).permit(:time_slot_array, :event_id)
  end
end
