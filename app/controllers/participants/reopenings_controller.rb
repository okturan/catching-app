module Participants
  # Reopen the time: the organizer withdraws the set window under the same
  # lock that set it, then every linked guest hears once and can paint again.
  # A pending event and a third attempt are refused by the model.
  class ReopeningsController < ApplicationController
    include ParticipantScoped

    EVERY_OFFER_PAST = "Every offered time has passed. Change the times.".freeze

    before_action :require_organizer!

    def create
      told = @event.announce_reopening!(@event.reopen!)

      redirect_to @participant, status: :see_other, notice: [
        "The set time was withdrawn.",
        "#{helpers.pluralize(told, "guest")} #{told == 1 ? "was" : "were"} told.",
        (EVERY_OFFER_PAST if @event.every_offer_past?)
      ].compact.join(" ")
    end
  end
end
