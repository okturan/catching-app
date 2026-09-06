module Participations
  # The organizer edits what guests read on the card: name, description,
  # place, link and planned length. Slot length and zone are facts here,
  # never fields. Allowed while pending or finalized, refused once cancelled.
  # A ticked notice[send] mails the guests once the change set is non-empty.
  class DetailsController < ParticipationScopedController
    before_action :require_organizer!
    before_action :refuse_cancelled, only: :edit

    helper_method :notice_offered?

    def edit
    end

    def update
      changes = @event.update_details!(details_params)
      notice = "Details saved."
      if notice_requested? && changes.any?
        result = Deliveries.event_updated!(event: @event, organizer: @participant, request_ip: request.remote_ip,
          reason: :details, changes: changes.to_h)
        notice += notice_report(result)
      end

      redirect_to scoped_path, notice: notice, status: :see_other
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_entity
    rescue Event::ClosedError => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    rescue ArgumentError => error
      # The details are saved; only the notice was refused.
      redirect_to scoped_path, notice: "Details saved.", alert: error.message, status: :see_other
    end

    private

    def details_params
      params.fetch(:event, {}).permit(:name, :description, :place, :place_url, :duration_minutes)
    end

    def notice_requested?
      params.dig(:notice, :send) == "1"
    end

    # The checkbox is offered only when a notice could reach anyone: the
    # organizer has opened their link and at least one guest holds one.
    def notice_offered?
      @participant.link_opened_at.present? && @event.guests.active.linked.exists?
    end
  end
end
