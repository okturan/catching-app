module Participations
  # Reopen the time: the organizer withdraws the set window under the same
  # lock that set it, then every linked guest hears once and can paint
  # again. No opened organizer link is required (as for cancel: without one
  # nobody else holds a link, and the batch is empty). A pending event and a
  # third attempt are refused by the model with the exact sentence.
  class ReopeningsController < ParticipationScopedController
    EVERY_OFFER_PAST = "Every offered time has passed. Change the times.".freeze

    before_action :require_organizer!

    def create
      previous_window = @event.reopen!
      told = Deliveries.reopened!(event: @event, previous_window: previous_window)

      notice = "The set time was withdrawn. #{told_sentence(told)}"
      notice += " #{EVERY_OFFER_PAST}" if @event.every_offer_past?
      redirect_to scoped_path, notice: notice, status: :see_other
    rescue ArgumentError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end

    private

    def told_sentence(count)
      count == 1 ? "1 guest was told." : "#{count} guests were told."
    end
  end
end
