module Participations
  class ParticipantsController < ParticipationScopedController
    # Organizer removes a guest. Ledger rows survive with participant_id NULL.
    def destroy
      require_organizer!
      guest = target_guest(params[:id])
      @event.with_lock { guest.destroy! }

      redirect_to scoped_path, notice: "#{guest.email} removed."
    end
  end
end
