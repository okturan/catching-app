module Participations
  class DeclinesController < ParticipationScopedController
    before_action :require_guest!

    def create
      first_reply = @participant.responded_at.nil?
      @event.mark_unavailable!(participant: @participant)
      @participant.update!(time_zone: params.dig(:participant, :time_zone).presence || @participant.time_zone)
      Deliveries.response_confirmation!(event: @event, guest: @participant) if first_reply

      redirect_to scoped_path, notice: "Saved. The organizer will see that none of these times work for you."
    end
  end
end
