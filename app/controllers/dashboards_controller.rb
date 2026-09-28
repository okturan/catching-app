class DashboardsController < ApplicationController
  def show
    participants = Current.user.participants.active.includes(event: :organizer).order(created_at: :desc)
    @organizing, @invited = participants.partition(&:organizer?)
    @guest_counts = Participant.guest.active.where(event_id: @organizing.map(&:event_id)).group(:event_id).count
  end
end
