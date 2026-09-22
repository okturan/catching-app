module Participants
  # "Show link to copy": an explicit, confirmed, recorded action. The URL is
  # rendered once as text and never travels through the flash.
  class LinkRevealsController < ApplicationController
    include ParticipantScoped
    include EventPage

    before_action :require_opened_organizer!

    def create
      @revealed_guest = target_guest(params[:guest_id])
      raw_token = @revealed_guest.reveal_link!(by: @participant, request_ip: request.remote_ip)
      @revealed_url = participant_url(raw_token)

      load_event_page
      render "participants/show"
    end
  end
end
