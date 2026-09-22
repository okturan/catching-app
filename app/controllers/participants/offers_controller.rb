module Participants
  # Change the times: the organizer repaints the offer on the same definer
  # that planned it, hydrated with every offered instant that is not yet
  # past. The step and zone stay live until the first guest reply.
  class OffersController < ApplicationController
    include ParticipantScoped

    before_action :require_organizer!
    before_action -> { @event.ensure_not_cancelled! }, only: :edit
    before_action :refuse_finalized

    helper_method :notice_offered?

    def edit
      load_offer_page
    end

    def update
      step = grid_params[:slot_minutes].presence&.to_i
      revision = @event.revise_offer!(starts_at: future_slots(step), slot_minutes: step, time_zone: grid_params[:time_zone].presence)
    rescue ActiveRecord::RecordInvalid
      render_offer_again
    rescue Refusal => refusal
      @event.errors.add(:base, refusal.message)
      render_offer_again
    else
      report = notify_guests(:offer) if revision.delta? && notice_requested?
      redirect_to @participant, notice: outcome(revision, report), status: :see_other
    end

    private

    # A set time is changed by reopening it, never by repainting the offer.
    def refuse_finalized
      if @event.finalized? && !@event.cancelled?
        redirect_to @participant, alert: "Reopen the time before changing the offer", status: :see_other
      end
    end

    # Step and zone are permitted only while no guest has replied.
    def grid_params
      @event.grid_frozen? ? {} : params.fetch(:event, {}).permit(:slot_minutes, :time_zone)
    end

    # The offer as submitted, minus instants that crossed the cut-off while
    # the page was open; revise_offer! leaves the past alone anyway.
    def future_slots(step)
      cutoff = TimeSlot::PAST_GRACE.ago
      slots = parsed_time_slots(slot_minutes: Event::SLOT_MINUTES.include?(step) ? step : @event.slot_minutes)
        .select { it >= cutoff }
      raise Refusal, "Select at least one time slot" if slots.empty?

      slots
    end

    def outcome(revision, report)
      voided = revision.voided_ids.size
      [
        revision,
        (report if report&.reached_anyone?),
        ("#{helpers.pluralize(voided, "guest")} #{voided == 1 ? "needs" : "need"} a new reply." if voided.positive?),
        ("Planned length cleared: it no longer fits #{@event.slot_minutes}-minute slots." if revision.duration_cleared)
      ].compact.join(" ")
    end

    def render_offer_again
      load_offer_page(echo: params.dig(:time_slots, :time_slot_array).to_s)
      render :edit, status: :unprocessable_entity
    end

    def load_offer_page(echo: nil)
      cutoff = TimeSlot::PAST_GRACE.ago
      offered = @event.organizer.available_start_times
      future = offered.select { it >= cutoff }
      @past_count = offered.size - future.size
      @current_offer = future.map(&:iso8601)
      @hydrated = echo || @current_offer.join(",")
      @begin_min = Time.current.in_time_zone(@event.time_zone).to_date.iso8601
      @guest_picked_counts = @event.time_slots.where(participant: @event.guests.counting).group(:start_time).count
        .transform_keys(&:iso8601)
    end

    def notice_requested?
      params.dig(:notice, :send) == "1"
    end

    # The checkbox is offered once the organizer has opened their link, the
    # one condition under which a notice can be sent at all.
    def notice_offered?
      @participant.link_opened_at?
    end
  end
end
