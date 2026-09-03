module Participations
  class FinalizationsController < ParticipationScopedController
    def create
      require_organizer!
      @event.finalize!(starts_at: parsed_time_slots(slot_minutes: @event.slot_minutes))
      Deliveries.finalized!(event: @event)

      redirect_to scoped_path, notice: "Meeting time confirmed."
    rescue ActiveRecord::RecordInvalid, ArgumentError, Event::ClosedError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end
  end
end
