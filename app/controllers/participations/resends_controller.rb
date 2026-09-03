module Participations
  class ResendsController < ParticipationScopedController
    def create
      require_opened_organizer!
      return if performed?

      guest = target_guest(params[:participant_id])
      Deliveries.invitation!(event: @event, guest: guest, organizer: @participant, request_ip: request.remote_ip)

      redirect_to scoped_path, notice: "Invitation sent again to #{guest.email}."
    rescue MailDelivery::CapExceeded, ArgumentError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end
  end
end
