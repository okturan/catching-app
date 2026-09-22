class ParticipationsController < ParticipationScopedController
  include ParticipationPage

  before_action :require_guest!, only: %i[update destroy]
  # Leave is the guest's kill switch and works on a cancelled event too.
  skip_before_action :ensure_event_not_cancelled, only: :destroy

  def show
    mark_link_opened if token_request? && @participant.organizer?
    load_participation_page
  end

  # Guest availability.
  def update
    starts_at = parsed_time_slots(slot_minutes: @event.slot_minutes)
    first_reply = @participant.responded_at.nil?

    @event.transaction do
      @event.replace_time_slots!(participant: @participant, starts_at:)
      # A revision that voided this guest may have committed between the load
      # above and the lock inside replace_time_slots!; reload so clearing
      # reply_voided_at is a real change and reaches the row.
      @participant.reload.update!(
        responded_at: Time.current,
        declined_at: nil,
        reply_voided_at: nil,
        name: params.dig(:participant, :name).presence || @participant.name,
        time_zone: params.dig(:participant, :time_zone).presence || @participant.time_zone
      )
    end
    Deliveries.response_confirmation!(event: @event, guest: @participant) if first_reply

    redirect_to scoped_path, notice: "Availability saved."
  end

  # Guest leaves for good.
  def destroy
    name = @event.name
    @participant.leave!

    redirect_to root_path, notice: "You left #{name}.", status: :see_other
  end

  private

  # Delivery proof: only a request through the emailed link counts.
  def mark_link_opened
    @participant.update_columns(link_opened_at: Time.current) unless @participant.link_opened_at?
  end
end
