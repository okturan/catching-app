# Everything at /p/:key. The key is an emailed link's token, which needs no
# session, or the participant's id, which only the claiming account opens.
module ParticipantScoped
  extend ActiveSupport::Concern

  included do
    include TimeSlotParams

    allow_unauthenticated_access if: :token_request?
    before_action :set_participant
    before_action :canonicalize_key, if: -> { request.get? }
    before_action :ensure_event_not_cancelled, unless: -> { request.get? }
    before_action :promote_pending_token, unless: -> { request.get? }
    before_action :no_store

    rate_limit to: 30, within: 1.minute, by: -> { params[:key] }, unless: -> { request.get? }

    rescue_from ActiveRecord::RecordNotFound do
      render "participants/not_found", status: :not_found
    end

    rescue_from Refusal do |refusal|
      redirect_to @participant, alert: refusal.message, status: :see_other
    end

    rescue_from ActiveRecord::RecordInvalid do |invalid|
      redirect_to @participant, alert: invalid.record.errors.full_messages.to_sentence, status: :see_other
    end

    helper_method :token_request?
  end

  private

  # A key of digits is a participant id; any other key is tried as a token.
  def token_request?
    !Participant.canonical_key(params[:key]).match?(/\A\d+\z/)
  end

  def set_participant
    @participant = if token_request?
      Participant.find_by_link_token(params[:key]) or raise ActiveRecord::RecordNotFound
    else
      Current.user.participants.active.find(params[:key])
    end
    @event = @participant.event
  end

  # "/p/<key>." from a mail client goes to the clean form.
  def canonicalize_key
    return if params[:key] == @participant.to_param

    redirect_to url_for(request.path_parameters.merge(key: @participant.to_param, only_path: true)), status: :see_other
  end

  # A cancelled event refuses every write but Leave and Claim, which skip this.
  def ensure_event_not_cancelled
    @event.ensure_not_cancelled!
  end

  def promote_pending_token
    @participant.promote_pending!(actor: Current.user) if @participant.found_by_pending_token?
  end

  def viewer_role
    @event.open? ? @participant.role : "viewer"
  end

  def require_guest!
    raise ActiveRecord::RecordNotFound unless @participant.guest?
  end

  def require_organizer!
    raise ActiveRecord::RecordNotFound unless @participant.organizer?
  end

  # Mail to guests waits until the organizer has proved their address.
  def require_opened_organizer!
    require_organizer!
    return if @participant.link_opened_at?

    redirect_to @participant, status: :see_other,
      alert: "Open the organizer link we emailed to #{@participant.email} to send invitations."
  end

  def target_guest(id)
    @event.guests.active.find(id)
  end

  # A refused notice becomes the alert; what was saved before it stays saved.
  def notify_guests(reason, changes: nil)
    @event.notify_guests!(reason:, by: @participant, request_ip: request.remote_ip, changes:)
  rescue Refusal => refusal
    flash[:alert] = refusal.message
    nil
  end
end
