class DashboardsController < ApplicationController
  def show
    @organizing, @invited = current_user.participants.active.includes(:event).order(created_at: :desc).partition(&:organizer?)
  end
end
