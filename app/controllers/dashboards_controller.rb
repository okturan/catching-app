class DashboardsController < ApplicationController
  def show
    @activities = Activity.all
  end
end
