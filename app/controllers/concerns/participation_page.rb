# Loads everything participations/show needs for the viewer's role.
module ParticipationPage
  extend ActiveSupport::Concern

  private

  def load_participation_page
    @organizer = @event.organizer
    @guests = @event.guests.order(:created_at)
    @role = viewer_role
    @plan = @event.plan_timeline

    offered = slot_instants(@organizer)
    @offered_slots = offered.map(&:iso8601)
    # Every offered instant is behind the parser's cut-off: nothing can be
    # painted or set until the organizer changes the times.
    @every_offer_past = @event.every_offer_past?
    @my_slots = slot_instants(@participant).map(&:iso8601)
    @revision_notice = revision_notice
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
        unsent: @event.participants.unsent.count,
        stale: @event.offer_revised_at ? active_guests.counting.where(responded_at: ...@event.offer_revised_at).count : 0,
        voided: active_guests.where.not(reply_voided_at: nil).count
      }
      # The Tell the guests reminder: a revision no mail batch has reached,
      # someone with a link to tell, and an event that is still on.
      @untold_changes = @event.revision > @event.notified_revision && !@event.cancelled? && @counts[:invited].positive?
    end
  end

  def slot_instants(participant)
    return [] unless participant

    @event.time_slots.where(participant_id: participant.id).order(:start_time).pluck(:start_time)
  end

  # What a guest who already replied must hear, while the event is open:
  # their reply was voided; the set time was withdrawn since they replied;
  # or the offer changed since they replied (a declined guest only when
  # times were added). When both a reopen and a revision postdate the reply
  # the later one speaks. Nil for the organizer, for a guest who never
  # replied, and once the guest has saved again.
  def revision_notice
    return nil unless @event.open? && @participant.guest? && @participant.responded_at.present?
    return :voided if @participant.reply_voided_at.present?

    reopened = @event.reopened_at.present? && @participant.responded_at < @event.reopened_at
    revised = @event.offer_revised_at.present? && @participant.responded_at < @event.offer_revised_at
    return :reopened if reopened && (!revised || @event.reopened_at > @event.offer_revised_at)
    return nil unless revised
    return :stale if @participant.declined_at.nil?

    @event.offer_revision_added.positive? ? :declined_added : nil
  end
end
