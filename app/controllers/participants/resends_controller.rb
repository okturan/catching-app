module Participants
  class ResendsController < ApplicationController
    include ParticipantScoped

    before_action :require_opened_organizer!

    def create
      guest = target_guest(params[:guest_id])
      guest.invite!(by: @participant, request_ip: request.remote_ip)

      redirect_to @participant, notice: "Invitation sent again to #{guest.email}.", status: :see_other
    end
  end
end
