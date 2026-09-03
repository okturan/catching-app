module Participations
  class DeclinesController < ParticipationScopedController
    def create
      require_guest!
      @event.mark_unavailable!(participant: @participant)
      @participant.update!(time_zone: params.dig(:participant, :time_zone).presence || @participant.time_zone)

      redirect_to scoped_path, notice: "Saved. The organizer will see that none of these times work for you."
    rescue ActiveRecord::RecordInvalid, Event::ClosedError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end
  end
end
