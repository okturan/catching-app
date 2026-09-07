module TimeSlotParams
  extend ActiveSupport::Concern

  private

  def parsed_time_slots(slot_minutes:)
    TimeSlotParser.call(params.require(:time_slots).fetch(:time_slot_array), slot_minutes: slot_minutes)
  rescue KeyError, TypeError
    raise ActionController::ParameterMissing, :time_slots
  end
end
