module Participations
  # The organizer edits what guests read on the card: name, description,
  # place, link and planned length. Slot length and zone are facts here,
  # never fields. Allowed while pending or finalized, refused once cancelled.
  class DetailsController < ParticipationScopedController
    before_action :require_organizer!
    before_action :refuse_cancelled

    def edit
    end

    def update
      @event.update_details!(details_params)

      redirect_to scoped_path, notice: "Details saved.", status: :see_other
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_entity
    rescue Event::ClosedError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end

    private

    def details_params
      params.fetch(:event, {}).permit(:name, :description, :place, :place_url, :duration_minutes)
    end
  end
end
