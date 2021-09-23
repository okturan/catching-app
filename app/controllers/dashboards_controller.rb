class DashboardsController < ApplicationController
  def show
    @activities = Activity.all
    @events = Event.all
  end
end
