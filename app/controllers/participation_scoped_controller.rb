# Base for both route families. A token request (/p/:token) needs no session
# and identifies the viewer by capability; a session request
# (/participations/:id) identifies the viewer through the signed-in account.
# Both resolve to one Participant row, and every action reads it as
# @participant with its event as @event.
class ParticipationScopedController < ApplicationController
  include TimeSlotParams

  skip_before_action :authenticate_user!, if: :token_request?
  before_action :set_participant
  before_action :canonicalize_token_path, if: :token_request?
  before_action :promote_pending_token, if: :token_request?, unless: -> { request.get? }
  after_action :forbid_caching

  rate_limit to: 30, within: 1.minute, unless: -> { request.get? },
    by: -> { request.path_parameters[:token] || request.remote_ip }

  rescue_from ActiveRecord::RecordNotFound, with: :render_link_not_found

  helper_method :token_request?, :scoped_path, :viewer_role

  private

  def token_request?
    request.path_parameters.key?(:token)
  end

  def set_participant
    if token_request?
      @resolution = Participant.resolve_token(params[:token])
      raise ActiveRecord::RecordNotFound unless @resolution

      @participant = @resolution.participant
    else
      @participant = current_user.participants.active.includes(:event).find(params[:participation_id])
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

  # The first write with a pending token makes it live and retires the old one.
  def promote_pending_token
    return unless @resolution.via_pending

    @participant.promote_pending!(Participant.digest(@resolution.canonical_token), actor: current_user)
  end

  def viewer_role
    @event.status? ? "viewer" : @participant.role
  end

  def scoped_path(name = nil, *args)
    helper = [ token_request? ? "participation" : "my_participation", name ].compact.join("_")
    viewer = token_request? ? @resolution.canonical_token : @participant
    public_send("#{helper}_path", viewer, *args)
  end

  def require_guest!
    raise ActiveRecord::RecordNotFound unless @participant.guest?
  end

  def require_organizer!
    raise ActiveRecord::RecordNotFound unless @participant.organizer?
  end

  def require_opened_organizer!
    require_organizer!
    return if @participant.link_opened_at.present?

    redirect_to scoped_path, status: :see_other,
      alert: "Open the organizer link we emailed to #{@participant.email} to send invitations."
  end

  def target_guest(id)
    @event.guests.active.find(id)
  end

  def forbid_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def render_link_not_found
    render "participations/not_found", status: :not_found
  end
end
