module Participants
  # Tell the guests: one coalesced notice about everything that changed since
  # the last mail reached them.
  class NoticesController < ApplicationController
    include ParticipantScoped

    before_action :require_organizer!

    def create
      if @event.revision == @event.notified_revision
        redirect_to @participant, alert: "Guests already know about every change.", status: :see_other
      else
        report = @event.notify_guests!(reason: :all, by: @participant, request_ip: request.remote_ip)
        redirect_to @participant, notice: report.to_s, status: :see_other
      end
    end
  end
end
