class ParticipantsController < ApplicationController
  include ParticipantScoped
  include EventPage

  before_action :require_guest!, only: %i[update destroy]
  # Leave is the guest's kill switch and works on a cancelled event too.
  skip_before_action :ensure_event_not_cancelled, only: :destroy

  def show
    mark_link_opened if token_request? && @participant.organizer?
    load_event_page
  end

  # A guest's painted times.
  def update
    @participant.reply!(parsed_time_slots(slot_minutes: @event.slot_minutes), params.fetch(:participant, {}).permit(:name, :time_zone))

    redirect_to @participant, notice: "Availability saved.", status: :see_other
  end

  # Guest leaves for good.
  def destroy
    @participant.leave!

    redirect_to root_path, notice: "You left #{@event.name}.", status: :see_other
  end

  private

  # Delivery proof: only a request through the emailed link counts.
  def mark_link_opened
    @participant.update_columns(link_opened_at: Time.current) unless @participant.link_opened_at?
  end
end
