class DashboardsController < ApplicationController
  def show
    @events = Event.accessible_to(current_user)
      .includes(:user, :invited_users)
      .order(created_at: :desc)
    @members = User.where.not(id: current_user.id).order(:first_name, :last_name)
  end
end
