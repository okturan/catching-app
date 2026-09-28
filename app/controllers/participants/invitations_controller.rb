module Participants
  # Invites every guest without a link yet, new addresses included.
  class InvitationsController < ApplicationController
    include ParticipantScoped

    before_action :require_opened_organizer!

    def create
      added, already = @event.add_guests!(Participant.addresses_from(params.dig(:invitations, :emails).to_s))
      guests = @event.participants.unsent.order(:created_at).to_a
      guests.each { it.invite!(by: @participant, request_ip: request.remote_ip) }

      redirect_to @participant, status: :see_other, notice: [
        ("#{added.size} added." if added.any?),
        "#{helpers.pluralize(guests.size, "invitation")} sent.",
        ("#{already.to_sentence} already on this event." if already.any?)
      ].compact.join(" ")
    end
  end
end
