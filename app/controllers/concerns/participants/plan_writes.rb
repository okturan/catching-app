# Shared by the two plan-editing controllers: organizer only, refused once
# cancelled by the base controller, and every outcome lands back on the
# Edit details page.
module Participants
  module PlanWrites
    extend ActiveSupport::Concern

    included do
      before_action :require_organizer!
      rescue_from ActiveRecord::RecordInvalid, with: :plan_refused
    end

    private

    def plan_updated
      redirect_to edit_participant_details_path(@participant), notice: "Plan updated.", status: :see_other
    end

    def plan_refused(error)
      redirect_to edit_participant_details_path(@participant), alert: error.record.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
