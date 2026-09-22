module Participations
  class ParticipantsController < ParticipationScopedController
    before_action :require_organizer!

    # Organizer removes a guest. Ledger rows survive with participant_id NULL.
    def destroy
      guest = target_guest(params[:id])
      @event.with_lock { guest.destroy! }

      redirect_to scoped_path, notice: "#{guest.email} removed.", status: :see_other
    end
  end
end
