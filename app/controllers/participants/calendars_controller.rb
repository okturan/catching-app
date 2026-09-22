module Participants
  class CalendarsController < ApplicationController
    include ParticipantScoped

    # The ".ics" must not choose the format: the 404 is the HTML page.
    before_action { request.format = :html }

    def show
      raise ActiveRecord::RecordNotFound unless @event.finalized?

      send_data CalendarFile.new(@event, mode: :page).body,
        type: "text/calendar; charset=utf-8", disposition: "attachment", filename: "#{@event.name.parameterize.presence || 'event'}.ics"
    end
  end
end
