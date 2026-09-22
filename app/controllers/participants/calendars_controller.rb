module Participants
  # The page-mode calendar file, for any participant of a finalized event. A
  # pending event answers the uniform 404; a cancelled finalized event serves
  # STATUS:CANCELLED so a re-import clears the entry.
  class CalendarsController < ApplicationController
    include ParticipantScoped

    # The ".ics" in the path must not choose the response format: the file
    # is sent with its own type and the uniform 404 is the HTML page.
    before_action { request.format = :html }

    def show
      raise ActiveRecord::RecordNotFound unless @event.finalized?

      send_data CalendarFile.new(@event, mode: :page).body,
        type: "text/calendar; charset=utf-8", disposition: "attachment", filename: "#{@event.name.parameterize.presence || 'event'}.ics"
    end
  end
end
