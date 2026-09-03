class ParticipationsController < ParticipationScopedController
  include ParticipationPage

  def show
    mark_link_opened if token_request? && @participant.organizer?
    load_participation_page
  end

  # Guest availability.
  def update
    require_guest!
    starts_at = parsed_time_slots(slot_minutes: @event.slot_minutes)
    first_reply = @participant.responded_at.nil?

    @event.transaction do
      @event.replace_time_slots!(participant: @participant, starts_at: starts_at)
      @participant.update!(
        responded_at: Time.current,
        declined_at: nil,
        name: params.dig(:participant, :name).presence || @participant.name,
        time_zone: params.dig(:participant, :time_zone).presence || @participant.time_zone
      )
    end
    Deliveries.response_confirmation!(event: @event, guest: @participant) if first_reply

    redirect_to scoped_path, notice: "Availability saved."
  rescue ActiveRecord::RecordInvalid, ArgumentError, Event::ClosedError => error
    redirect_to scoped_path, alert: error.message, status: :see_other
  end

  # Guest leaves for good.
  def destroy
    require_guest!
    name = @event.name
    @participant.leave!

    redirect_to root_path, notice: "You left #{name}.", status: :see_other
  end

  private

  # Delivery proof: only a request through the emailed link counts.
  def mark_link_opened
    return if @participant.link_opened_at.present?

    @participant.update_columns(link_opened_at: Time.current)
  end
end
