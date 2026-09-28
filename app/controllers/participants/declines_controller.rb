module Participants
  class DeclinesController < ApplicationController
    include ParticipantScoped

    before_action :require_guest!

    def create
      @participant.decline!(params.fetch(:participant, {}).permit(:time_zone))

      redirect_to @participant, notice: "Saved. The organizer will see that none of these times work for you.", status: :see_other
    end
  end
end
