module Participations
  # "Show link to copy": an explicit, confirmed, recorded action. The URL is
  # rendered once as text and never travels through the flash.
  class LinkRevealsController < ParticipationScopedController
    include ParticipationPage

    def create
      require_opened_organizer!
      return if performed?

      guest = target_guest(params[:participant_id])
      raw_token = Deliveries.reveal_link!(event: @event, guest: guest, organizer: @participant, request_ip: request.remote_ip)
      @revealed_url = participation_url(raw_token)
      @revealed_guest = guest

      load_participation_page
      render "participations/show"
    rescue ArgumentError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end
  end
end
