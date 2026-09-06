module Participations
  # The organizer's plan editor: add, change and remove one item. Items are
  # found through the event, so another event's item is a 404 like any
  # other bad link.
  class ActivitiesController < ParticipationScopedController
    include PlanWrites

    def create
      @event.add_plan_item!(activity_params)
      plan_updated
    end

    def update
      @event.update_plan_item!(activity, activity_params)
      plan_updated
    end

    def destroy
      @event.remove_plan_item!(activity)
      plan_updated
    end

    private

    def activity
      @event.activities.find(params[:id])
    end

    def activity_params
      params.require(:activity).permit(:name, :duration, :description)
    end
  end
end
