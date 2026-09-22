module Participations
  # The organizer's plan editor: add, change and remove one item. Items are
  # found through the event, so another event's item is a 404 like any
  # other bad link.
  class PlanItemsController < ParticipationScopedController
    include PlanWrites

    def create
      @event.add_plan_item!(plan_item_params)
      plan_updated
    end

    def update
      @event.update_plan_item!(plan_item, plan_item_params)
      plan_updated
    end

    def destroy
      @event.remove_plan_item!(plan_item)
      plan_updated
    end

    private

    def plan_item
      @event.plan_items.find(params[:id])
    end

    def plan_item_params
      params.expect(plan_item: %i[name duration_minutes description])
    end
  end
end
