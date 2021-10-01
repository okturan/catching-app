class EventsController < ApplicationController
  def create
    # Create new event with only event_params
    @event = Event.new(event_params)
    @event.user = current_user
    @event.save

    # Create timeslots with time_slot_array_params and with the event created above
    @time_slot_array = time_slot_array_params[:time_slot_array]
    @time_slots = @time_slot_array.split(',')
    @time_slots.each do |slot|
      time_slot = TimeSlot.new(start_time: slot, user: current_user, event: @event)
      time_slot.save
    end
    @user_list_array = user_info_params[:user_list_array]
    @user_list = @user_list_array.split(',')
    @user_list.each do |user|
      invited_user = User.find(user)
      @event.invite(invited_user)
    end

    # if all the users invited to the event has cast a vote then change the status to true
    # @arr = []
    # @event.invited_users.each do |invited_user|
    #   if @event.time_slots.include?(invited_user.time_slots)
    #     @arr << "yay"
    #   else
    #     @arr << "nay"
    #   end

    # end

    redirect_to dashboard_path
  end

  def show
    # Seperate time slots by user
    # @time_slots sort by user_id
    @event = Event.find(params[:id])
    @host = @event.user
    @host_time_slots = @event.time_slots.where(user: @host)

    @guest_time_slots = @event.time_slots - @host_time_slots

    @guests = @event.invited_users
  end

  def new
    @users = User.all - [current_user]
    @event = Event.new
  end

  def update
    @event = Event.find(params[:id])
    @final_time_slots = time_slot_array_params[:time_slot_array]

    @final_time_slot_array = @final_time_slots.split(',')

    @event.start_time = @final_time_slot_array.first
    @event.end_time = @final_time_slot_array.last
    @event.status = true

    @event.save!

    redirect_to dashboard_path
  end

  private

  def event_params
    params.require(:event).permit(:name, :description)
  end

  def time_slot_array_params
    params.require(:time_slots).permit(:time_slot_array)
  end

  def user_info_params
    params.require(:user_list).permit(:user_list_array)
  end
end
