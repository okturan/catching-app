class DashboardsController < ApplicationController
  def show
    @activities = Activity.all
    # @events_invited = Event.all
    # events = Arel::Table.new("events")
    # invitations = Arel::Table.new("invitations")
    # # users = Arel::Table.new("users")

    # events_invitations = events.join(invitations).on(events[:id].eq(invitations[:user_id]))

    # invited = events_invitations.where(invitations[:user_id].eq(2))

    # invitations_query = invitations[:user_id].eq("2")
    # @invitations = Invitation.where(invitations_query)

  

    # events_query = events[:user_id].eq(current_user.id)
    # @events_hosted = Event.where(events_query)



    # @events = @events_invited + @events_hosted
    # @events = @events.to_a.uniq

    @events = current_user.events + current_user.invited_events

  end
end
