module Participations
  # Adds any new addresses, then sends an invitation to every guest without a
  # live link. Nothing leaves before the organizer has opened the emailed link.
  class InvitationsController < ParticipationScopedController
    before_action :require_opened_organizer!

    def create
      added, already = @event.add_guests!(Participant.addresses_from(params.dig(:invitations, :emails).to_s))
      guests = @event.participants.unsent.order(:created_at).to_a
      guests.each { Deliveries.invitation!(event: @event, guest: it, organizer: @participant, request_ip: request.remote_ip) }

      redirect_to scoped_path, notice: [
        ("#{added.size} added." if added.any?),
        "#{helpers.pluralize(guests.size, "invitation")} sent.",
        ("#{already.to_sentence} already on this event." if already.any?)
      ].compact.join(" ")
    end
  end
end
