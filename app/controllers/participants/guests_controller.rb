module Participants
  class GuestsController < ApplicationController
    include ParticipantScoped

    before_action :require_organizer!

    # The ledger keeps the guest's rows, with no participant.
    def destroy
      guest = target_guest(params[:id])
      @event.with_lock { guest.destroy! }

      redirect_to @participant, notice: "#{guest.email} removed.", status: :see_other
    end
  end
end
