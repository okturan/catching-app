module Participations
  # Change the times: the organizer repaints the offer on the same definer
  # that planned it, hydrated with every offered instant that is not yet
  # past. Organizer only, while the event is open; a finalized event asks
  # for a reopen first and a cancelled one answers the cancelled alert. The
  # step and zone stay live until the first guest reply and are neither
  # rendered enabled nor permitted afterwards.
  class OffersController < ParticipationScopedController
    REOPEN_FIRST = "Reopen the time before changing the offer".freeze

    before_action :require_organizer!
    before_action :refuse_cancelled, only: :edit
    before_action :refuse_finalized

    helper_method :notice_offered?, :grid_frozen?

    def edit
      load_offer_page
    end

    def update
      requested = offer_params
      step = requested[:slot_minutes].presence&.to_i
      starts_at = parsed_time_slots(slot_minutes: Event::SLOT_MINUTES.include?(step) ? step : @event.slot_minutes)
      # An instant can cross the cut-off while the page is open; revise_offer!
      # freezes the past anyway, so drop them instead of refusing the save.
      cutoff = TimeSlotParser::PAST_GRACE.ago
      starts_at = starts_at.select { |instant| instant >= cutoff }
      raise ArgumentError, "Select at least one time slot" if starts_at.empty?
      revision = @event.revise_offer!(starts_at: starts_at, slot_minutes: step, time_zone: requested[:time_zone].presence)

      notice = outcome_sentence(revision)
      alert = nil
      if revision.delta? && notice_requested?
        begin
          result = Deliveries.event_updated!(event: @event, organizer: @participant, request_ip: request.remote_ip, reason: :offer)
          # Before the first reply there is nobody to tell; the flash says nothing.
          notice += notice_report(result) if result.values.sum.positive?
        rescue ArgumentError => error
          alert = error.message
        end
      end
      voided = revision.voided_ids.size
      notice += " #{voided} #{'guest'.pluralize(voided)} #{voided == 1 ? 'needs' : 'need'} a new reply." if voided.positive?
      notice += " Planned length cleared: it no longer fits #{@event.slot_minutes}-minute slots." if revision.duration_cleared

      redirect_to scoped_path, notice: notice, alert: alert, status: :see_other
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      # The parser, the grid, the frozen step or zone and the slot cap: the
      # paint comes back with the message so nothing is lost.
      @event.errors.add(:base, error.message) unless error.is_a?(ActiveRecord::RecordInvalid)
      load_offer_page(echo: params.dig(:time_slots, :time_slot_array).to_s)
      render :edit, status: :unprocessable_entity
    end

    private

    # A set time is changed by reopening it, never by repainting the offer.
    def refuse_finalized
      return unless @event.status? && !@event.cancelled?

      redirect_to scoped_path, alert: REOPEN_FIRST, status: :see_other
    end

    def load_offer_page(echo: nil)
      cutoff = TimeSlotParser::PAST_GRACE.ago
      offered = @event.time_slots.where(participant_id: @event.organizer.id).order(:start_time).pluck(:start_time)
      future = offered.select { |start_time| start_time >= cutoff }
      @past_count = offered.size - future.size
      @current_offer = future.map(&:iso8601)
      @hydrated = echo.nil? ? @current_offer.join(",") : echo
      @not_before = cutoff.utc.iso8601
      @begin_min = Time.current.in_time_zone(@event.time_zone).to_date.iso8601
      holders = @event.participants.guest.where(left_at: nil, declined_at: nil).where.not(responded_at: nil).select(:id)
      @guest_picked_counts = @event.time_slots.where(participant_id: holders).group(:start_time).count.transform_keys(&:iso8601)
    end

    def outcome_sentence(revision)
      if revision.delta?
        "Times updated: #{revision.added.size} added, #{revision.removed.size} removed."
      elsif revision.grid_changed
        "Slot length and zone updated."
      else
        "Nothing changed."
      end
    end

    # Step and zone are permitted only while no guest has replied.
    def offer_params
      params.fetch(:event, {}).permit(*(grid_frozen? ? [] : %i[slot_minutes time_zone]))
    end

    def grid_frozen?
      return @grid_frozen if defined?(@grid_frozen)

      @grid_frozen = @event.participants.guest.where.not(responded_at: nil).exists?
    end

    def notice_requested?
      params.dig(:notice, :send) == "1"
    end

    # The checkbox is offered once the organizer has opened their link, the
    # one condition under which a notice can be sent at all.
    def notice_offered?
      @participant.link_opened_at.present?
    end
  end
end
