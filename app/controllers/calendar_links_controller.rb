# The calendar file a mail links to. See CalendarLink.
class CalendarLinksController < ApplicationController
  allow_unauthenticated_access

  def show
    file = CalendarLink.file_for(params[:token])
    return head :not_found unless file

    response.headers["Cache-Control"] = "no-store"
    send_data file.body, type: "text/calendar; charset=utf-8", disposition: "attachment",
      filename: "#{file.event.name.parameterize.presence || 'event'}.ics"
  end
end
