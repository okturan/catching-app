module Participations
  # Links a token participation to the signed-in account. Binding is by
  # token possession only; email equality never links anything.
  class ClaimsController < ParticipationScopedController
    before_action :authenticate_user!

    def show
      redirect_to my_participation_path(@participant), notice: "This event is already in your account." if claimed_by_current_user?
    end

    def create
      claimed = @event.with_lock do
        Participant.where(id: @participant.id, user_id: nil, left_at: nil)
          .update_all(user_id: current_user.id, updated_at: Time.current)
      end

      if claimed == 1
        redirect_to my_participation_path(@participant), notice: "Saved to your account."
      else
        @participant.reload
        explain_failed_claim
      end
    rescue ActiveRecord::RecordNotUnique
      other = current_user.participants.find_by(event_id: @event.id)
      flash.now[:alert] = "You already take part in this event as #{other&.email}"
      render :show, status: :unprocessable_entity
    end

    private

    def claimed_by_current_user?
      @participant.user_id == current_user.id
    end

    def explain_failed_claim
      if claimed_by_current_user?
        redirect_to my_participation_path(@participant), notice: "This event is already in your account."
      elsif @participant.left?
        flash.now[:alert] = "This link can no longer be claimed"
        render :show, status: :unprocessable_entity
      else
        flash.now[:alert] = "This invitation is already linked to another account"
        render :show, status: :unprocessable_entity
      end
    end
  end
end
