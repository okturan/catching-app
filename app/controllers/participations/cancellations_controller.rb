module Participations
  # The organizer calls the event off: one locked write, then one last mail
  # to everyone with a link, the organizer included as a receipt. No opened
  # organizer link is required, since without one nobody else has a link.
  class CancellationsController < ParticipationScopedController
    before_action :require_organizer!

    def create
      @event.cancel!
      told = Deliveries.cancelled!(event: @event)

      redirect_to scoped_path, notice: "Event cancelled. #{told_sentence(told)}", status: :see_other
    end

    private

    def told_sentence(count)
      count == 1 ? "1 person was told." : "#{count} people were told."
    end
  end
end
