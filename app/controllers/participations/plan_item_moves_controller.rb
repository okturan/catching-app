module Participations
  # One POST per rearrangement: move[position] names the target index and
  # the model clamps it, so Up on the first item is a harmless no-op.
  class PlanItemMovesController < ParticipationScopedController
    include PlanWrites

    def create
      if (position = Integer(params.dig(:move, :position), exception: false))
        @event.move_plan_item!(@event.plan_items.find(params[:plan_item_id]), position)
        plan_updated
      else
        redirect_to scoped_path(:details, edit: true), alert: "Pick a position for the item", status: :see_other
      end
    end
  end
end
