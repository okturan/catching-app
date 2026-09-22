module Participants
  # Items are found through the event, so another event's item is a 404.
  class PlanItemsController < ApplicationController
    include ParticipantScoped
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
