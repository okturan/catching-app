module Participations
  # One POST per rearrangement: move[position] names the target index and
  # the model clamps it, so Up on the first item is a harmless no-op.
  class ActivityMovesController < ParticipationScopedController
    include PlanWrites

    def create
      position = Integer(params.dig(:move, :position), exception: false)
      if position.nil?
        redirect_to scoped_path(:details, edit: true), alert: "Pick a position for the item", status: :see_other
        return
      end

      @event.move_plan_item!(@event.activities.find(params[:activity_id]), position)
      plan_updated
    end
  end
end
