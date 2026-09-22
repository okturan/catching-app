module Participations
  class FinalizationsController < ParticipationScopedController
    before_action :require_organizer!

    def create
      @event.finalize!(starts_at: parsed_time_slots(slot_minutes: @event.slot_minutes))
      @event.announce_finalization!

      redirect_to scoped_path, notice: "Meeting time confirmed.", status: :see_other
    end
  end
end
