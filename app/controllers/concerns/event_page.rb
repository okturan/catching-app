# What participants/show needs for the viewer's role.
module EventPage
  extend ActiveSupport::Concern

  private

  def load_event_page
    @organizer = @event.organizer
    @guests = @event.guests.order(:created_at)
    @role = viewer_role
    @plan = @event.plan_timeline
    @every_offer_past = @event.every_offer_past?
    load_grid
    load_guest_table if @participant.organizer?
    @grid_notice = grid_notice
    @grid_action = grid_action
  end

  def load_grid
    @offered_slots = @organizer.available_start_times.map(&:iso8601)
    @my_slots = @participant.available_start_times.map(&:iso8601)
    @consensus_slots = @event.mutually_available_start_times.map(&:iso8601)
    @set_window = [ @event.start_time, @event.end_time ].map(&:iso8601) if @event.finalized?
    others = @event.participants.counting.where.not(id: @participant.id).select(:id)
    @availability_counts = @event.time_slots.where(participant_id: others).group(:start_time).count.transform_keys(&:iso8601)
  end

  def load_guest_table
    @invitations = @event.mail_deliveries.invitation.order(:created_at).group_by(&:participant_id)
    @slot_counts = @event.time_slots.group(:participant_id).count
    active_guests = @event.guests.active
    @counts = {
      invited: active_guests.linked.count,
      replied: active_guests.counting.count,
      declined: active_guests.where.not(declined_at: nil).count,
      unsent: @event.participants.unsent.count,
      stale: @event.offer_revised_at ? active_guests.counting.where(responded_at: ...@event.offer_revised_at).count : 0,
      voided: active_guests.where.not(reply_voided_at: nil).count
    }
    # A revision no mail has reached, someone to tell, and an event still on.
    @untold_changes = @event.revision > @event.notified_revision && !@event.cancelled? && @counts[:invited].positive?
  end

  # When every offered time has passed, "save again" would be a lie.
  def grid_notice
    return if @every_offer_past

    if @participant.organizer?
      :unanswered if @event.open? && (@counts[:stale] + @counts[:voided]).positive?
    else
      revision_notice
    end
  end

  def grid_action
    return unless @event.open?
    return :save if @participant.guest?
    return :change_the_times if @every_offer_past
    return :set_in_stone if @counts[:replied].positive?

    @counts[:voided].positive? ? :awaiting_answers : :awaiting_replies
  end

  # When both a reopen and a revision came after the reply, the later speaks.
  def revision_notice
    return unless @event.open? && @participant.guest? && @participant.responded_at?
    return :voided if @participant.voided?

    reopened = @participant.replied_before_reopen?
    revised = @participant.replied_before_revision?
    return :reopened if reopened && (!revised || @event.reopened_at > @event.offer_revised_at)
    return unless revised
    return :stale unless @participant.declined_at?

    :declined_added if @event.offer_revision_added.positive?
  end
end
