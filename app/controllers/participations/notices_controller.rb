module Participations
  # Tell the guests: one coalesced notice about everything that changed
  # since the last mail reached them. Organizer only; nothing to tell
  # answers without sending. Deliveries refuses an organizer who has not
  # opened their link, and the refusal lands on the page as the hint.
  class NoticesController < ParticipationScopedController
    NOTHING_TO_TELL = "Guests already know about every change.".freeze

    before_action :require_organizer!

    def create
      if @event.revision == @event.notified_revision
        return redirect_to scoped_path, alert: NOTHING_TO_TELL, status: :see_other
      end

      result = Deliveries.event_updated!(event: @event, organizer: @participant, request_ip: request.remote_ip, reason: :all)

      redirect_to scoped_path, notice: notice_report(result).strip, status: :see_other
    rescue ArgumentError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end
  end
end
