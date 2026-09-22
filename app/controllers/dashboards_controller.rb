class DashboardsController < ApplicationController
  def show
    participations = current_user.participants.active.includes(event: :organizer).order(created_at: :desc)
    @organizing, @invited = participations.partition(&:organizer?)
    @guest_counts = Participant.guest.active.where(event_id: @organizing.map(&:event_id)).group(:event_id).count
  end
end
