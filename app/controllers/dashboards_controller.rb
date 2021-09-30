class DashboardsController < ApplicationController
  def show
    @activities = Activity.all
    @events = current_user.events + current_user.invited_events
    @friends = User.all
  end
end
