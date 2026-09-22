module Participations
  # "Show link to copy": an explicit, confirmed, recorded action. The URL is
  # rendered once as text and never travels through the flash.
  class LinkRevealsController < ParticipationScopedController
    include ParticipationPage

    before_action :require_opened_organizer!

    def create
      @revealed_guest = target_guest(params[:participant_id])
      raw_token = Deliveries.reveal_link!(event: @event, guest: @revealed_guest, organizer: @participant, request_ip: request.remote_ip)
      @revealed_url = participation_url(raw_token)

      load_participation_page
      render "participations/show"
    end
  end
end
