class TimeSlotsController < ApplicationController
  def create
    event = current_user.invited_events.find(params[:event_id])
    event.replace_time_slots!(user: current_user, starts_at: parsed_time_slots)

    redirect_to event, notice: "Availability saved."
  rescue ActiveRecord::RecordInvalid, ArgumentError, Event::ClosedError => error
    redirect_to event_path(params[:event_id]), alert: error.message, status: :see_other
  end

  private

  def parsed_time_slots
    TimeSlotParser.call(params.require(:time_slots).fetch(:time_slot_array))
  rescue KeyError, TypeError
    raise ActionController::ParameterMissing, :time_slots
  end
end
