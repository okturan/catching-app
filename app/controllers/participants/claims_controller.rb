module Participants
  # Keeps a participant reached by link in the signed-in account. Binding is
  # by token possession only; email equality never links anything. Once kept,
  # the account's address for it is its id.
  class ClaimsController < ApplicationController
    include ParticipantScoped

    before_action :require_authentication
    # Memory stays allowed: a cancelled event can still be kept in an account.
    skip_before_action :ensure_event_not_cancelled

    def show
      redirect_to participant_path(@participant.id), notice: "This event is already in your account." if claimed_by_current_user?
    end

    def create
      claimed = @event.with_lock do
        Participant.where(id: @participant.id, user_id: nil, left_at: nil)
          .update_all(user_id: Current.user.id, updated_at: Time.current)
      end

      if claimed == 1
        redirect_to participant_path(@participant.id), notice: "Saved to your account.", status: :see_other
      else
        @participant.reload
        explain_failed_claim
      end
    rescue ActiveRecord::RecordNotUnique
      other = Current.user.participants.find_by(event_id: @event.id)
      flash.now[:alert] = "You already take part in this event as #{other.email}"
      render :show, status: :unprocessable_entity
    end

    private

    def claimed_by_current_user?
      @participant.user_id == Current.user.id
    end

    def explain_failed_claim
      if claimed_by_current_user?
        redirect_to participant_path(@participant.id), notice: "This event is already in your account.", status: :see_other
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
