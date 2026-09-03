class DashboardsController < ApplicationController
  def show
    participations = current_user.participants.active.includes(:event).order(created_at: :desc)
    @organizing = participations.select(&:organizer?)
    @invited = participations.select(&:guest?)
  end
end
