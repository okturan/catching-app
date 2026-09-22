module Participations
  class ResendsController < ParticipationScopedController
    before_action :require_opened_organizer!

    def create
      guest = target_guest(params[:participant_id])
      Deliveries.invitation!(event: @event, guest:, organizer: @participant, request_ip: request.remote_ip)

      redirect_to scoped_path, notice: "Invitation sent again to #{guest.email}."
    end
  end
end
