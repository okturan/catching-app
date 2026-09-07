# Shared by the two plan-editing controllers: organizer only, refused once
# cancelled by the base controller, and every outcome lands back on the
# Edit details page.
module Participations
  module PlanWrites
    extend ActiveSupport::Concern

    included do
      before_action :require_organizer!
      rescue_from ActiveRecord::RecordInvalid, with: :plan_refused
    end

    private

    def plan_updated
      redirect_to scoped_path(:details, edit: true), notice: "Plan updated.", status: :see_other
    end

    def plan_refused(error)
      redirect_to scoped_path(:details, edit: true), alert: error.record.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
