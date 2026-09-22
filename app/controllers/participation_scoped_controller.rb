# Base for both route families. A token request (/p/:token) needs no session
# and identifies the viewer by capability; a session request
# (/participations/:id) identifies the viewer through the signed-in account.
# Both resolve to one Participant row, read as @participant, with its event
# as @event.
class ParticipationScopedController < ApplicationController
  include TimeSlotParams

  allow_unauthenticated_access if: :token_request?
  before_action :set_participant
  before_action :canonicalize_token_path, if: :token_request?
  before_action :ensure_event_not_cancelled, unless: -> { request.get? }
  before_action :promote_pending_token, if: :token_request?, unless: -> { request.get? }
  before_action :no_store

  rate_limit to: 30, within: 1.minute, unless: -> { request.get? },
    by: -> { request.path_parameters[:token] || request.remote_ip }

  rescue_from ActiveRecord::RecordNotFound do
    render "participations/not_found", status: :not_found
  end

  rescue_from Refusal do |refusal|
    redirect_to scoped_path, alert: refusal.message, status: :see_other
  end

  rescue_from ActiveRecord::RecordInvalid do |invalid|
    redirect_to scoped_path, alert: invalid.record.errors.full_messages.to_sentence, status: :see_other
  end

  helper_method :token_request?, :scoped_path

  private

  def token_request?
    request.path_parameters.key?(:token)
  end

  def set_participant
    if token_request?
      @resolution = Participant.resolve_token(params[:token]) or raise ActiveRecord::RecordNotFound
      @participant = @resolution.participant
    else
      @participant = Current.user.participants.active.includes(:event).find(params[:participation_id])
    end
    @event = @participant.event
  end

  # A link mangled by a mail client ("/p/<token>.") resolves and is sent to
  # its canonical form.
  def canonicalize_token_path
    return unless request.get? && @resolution.canonical_token != params[:token]

    redirect_to url_for(request.path_parameters.merge(token: @resolution.canonical_token, only_path: true)),
      status: :see_other
  end

  # A cancelled event refuses every write but Leave and Claim, which skip this.
  def ensure_event_not_cancelled
    @event.ensure_not_cancelled!
  end

  # The first write with a pending token makes it live and retires the old one.
  def promote_pending_token
    return unless @resolution.via_pending

    @participant.promote_pending!(Participant.digest(@resolution.canonical_token), actor: Current.user)
  end

  # Painting needs an open event; finalized and cancelled pages are read.
  def viewer_role
    @event.open? ? @participant.role : "viewer"
  end

  # Path to a nested action in the viewer's own route family; edit: true names
  # the edit page of a singular resource (edit_participation_details_path).
  def scoped_path(name = nil, *args, edit: false)
    helper = [ ("edit" if edit), (token_request? ? "participation" : "my_participation"), name ].compact.join("_")
    viewer = token_request? ? @resolution.canonical_token : @participant
    public_send("#{helper}_path", viewer, *args)
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

    redirect_to scoped_path, status: :see_other,
      alert: "Open the organizer link we emailed to #{@participant.email} to send invitations."
  end

  def target_guest(id)
    @event.guests.active.find(id)
  end

  # Mails a change notice and returns the sentence that reports it. A refused
  # notice becomes the alert; whatever was saved before it stays saved.
  def notify_guests(reason, changes: nil)
    Deliveries.event_updated!(event: @event, organizer: @participant, request_ip: request.remote_ip, reason:, changes:)
  rescue Refusal => refusal
    flash[:alert] = refusal.message
    nil
  end
end
