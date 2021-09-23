class TimeSlotsController < ApplicationController
  def create
    user = User.last
    event = Event.last

    @time_slots = params[:time_slot][:array]
    @time_slots = @time_slots.split(',')

    @time_slots.each do |slot|
      time_slot = TimeSlot.new(start_time: slot, user: user, event: event)

      time_slot.save!
    end

  end
end
