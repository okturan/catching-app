module Participants
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
