module Participants
  class DetailsController < ApplicationController
    include ParticipantScoped

    before_action :require_organizer!
    before_action -> { @event.ensure_not_cancelled! }, only: :edit

    helper_method :notice_offered?

    def edit
    end

    def update
      changes = @event.update_details!(details_params)
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_entity
    else
      report = notify_guests(:details, changes:) if notice_requested? && changes.any?
      redirect_to @participant, notice: [ "Details saved.", report ].compact.join(" "), status: :see_other
    end

    private

    def details_params
      params.expect(event: %i[name description place place_url duration_minutes])
    end

    def notice_requested?
      params.dig(:notice, :send) == "1"
    end

    # Only when a notice could reach anyone.
    def notice_offered?
      @participant.link_opened_at? && @event.guests.active.linked.exists?
    end
  end
end
