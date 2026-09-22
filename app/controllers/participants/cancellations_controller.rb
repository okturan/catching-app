module Participants
  # The organizer calls the event off: one locked write, then one last mail
  # to everyone with a link, the organizer included as a receipt.
  class CancellationsController < ApplicationController
    include ParticipantScoped

    before_action :require_organizer!

    def create
      @event.cancel!
      told = @event.announce_cancellation!

      redirect_to @participant, status: :see_other,
        notice: "Event cancelled. #{helpers.pluralize(told, "person", plural: "people")} #{told == 1 ? "was" : "were"} told."
    end
  end
end
