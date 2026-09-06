# Loads everything participations/show needs for the viewer's role.
module ParticipationPage
  extend ActiveSupport::Concern

  private

  def load_participation_page
    @organizer = @event.organizer
    @guests = @event.guests.order(:created_at)
    @role = viewer_role
    @plan = @event.plan_timeline

    @offered_slots = slot_times(@organizer)
    @my_slots = slot_times(@participant)
    @consensus_slots = @event.mutually_available_start_times.map(&:iso8601)
    others = @event.participants.counting.where.not(id: @participant.id).select(:id)
    @availability_counts = @event.time_slots.where(participant_id: others).group(:start_time).count.transform_keys(&:iso8601)

    if @participant.organizer?
      @deliveries = @event.mail_deliveries.where(kind: %w[invitation]).order(:created_at)
        .group_by(&:participant_id)
      active_guests = @event.guests.active
      @counts = {
        invited: active_guests.linked.count,
        replied: active_guests.counting.count,
        declined: active_guests.where.not(declined_at: nil).count,
        unsent: @event.participants.unsent.count
      }
      # The Tell the guests reminder: a revision no mail batch has reached,
      # someone with a link to tell, and an event that is still on.
      @untold_changes = @event.revision > @event.notified_revision && !@event.cancelled? && @counts[:invited].positive?
    end
  end

  def slot_times(participant)
    return [] unless participant

    @event.time_slots.where(participant_id: participant.id).order(:start_time).pluck(:start_time).map(&:iso8601)
  end

  # Delivery state for the organizer table.
  def guest_state(guest)
    return :left if guest.left?
    return :declined if guest.declined_at.present?
    return :replied if guest.responded_at.present?
    return :not_sent if guest.token_digest.nil?

    last = (@deliveries[guest.id] || []).last
    last ? last.state : :queued
  end
end
