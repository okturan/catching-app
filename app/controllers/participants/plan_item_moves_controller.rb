module Participants
  # The model clamps the position, so Up on the first item does nothing.
  class PlanItemMovesController < ApplicationController
    include ParticipantScoped
    include PlanWrites

    def create
      if (position = Integer(params.dig(:move, :position), exception: false))
        @event.move_plan_item!(@event.plan_items.find(params[:plan_item_id]), position)
        plan_updated
      else
        redirect_to edit_participant_details_path(@participant), alert: "Pick a position for the item", status: :see_other
      end
    end
  end
end
