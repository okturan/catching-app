# Base for both route families. A token request (/p/:token) needs no session
# and identifies the viewer by capability; a session request
# (/participations/:id) identifies the viewer through the signed-in account.
# Both resolve to one Participant row, and every action reads it as
# @participant with its event as @event.
class ParticipationScopedController < ApplicationController
  include TimeSlotParams

  CANCELLED_MESSAGE = "This event was cancelled".freeze

  skip_before_action :authenticate_user!, if: :token_request?
  before_action :set_participant
  before_action :canonicalize_token_path, if: :token_request?
  before_action :refuse_closed_writes, unless: -> { request.get? }
  before_action :promote_pending_token, if: :token_request?, unless: -> { request.get? }
  after_action :forbid_caching

  rate_limit to: 30, within: 1.minute, unless: -> { request.get? },
    by: -> { request.path_parameters[:token] || request.remote_ip }

  rescue_from ActiveRecord::RecordNotFound, with: :render_link_not_found
  rescue_from Event::ClosedError, with: :event_closed

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

  # Painting needs an open event; finalized and cancelled pages are read.
  def viewer_role
    @event.open? ? @participant.role : "viewer"
  end

  # Path to a nested action in the viewer's own route family; edit: true names
  # the edit page of a singular resource (edit_participation_details_path).
  def scoped_path(name = nil, *args, edit: false)
    helper = [ (edit ? "edit" : nil), token_request? ? "participation" : "my_participation", name ].compact.join("_")
    viewer = token_request? ? @resolution.canonical_token : @participant
    public_send("#{helper}_path", viewer, *args)
  end

  def require_guest!
    raise ActiveRecord::RecordNotFound unless @participant.guest?
  end

  def require_organizer!
    raise ActiveRecord::RecordNotFound unless @participant.organizer?
  end

  # Every write on a cancelled event answers one alert, before any token is
  # promoted or any row touched. Leave (ParticipationsController#destroy)
  # and Claim (Participations::ClaimsController) skip this callback: the
  # guest's kill switch and memory stay available. Reads keep working for
  # every valid link.
  def refuse_closed_writes
    refuse_cancelled
  end

  # The same alert for organizer pages whose GET must refuse as well
  # (Edit details).
  def refuse_cancelled
    return unless @event.cancelled?

    redirect_to scoped_path, alert: CANCELLED_MESSAGE, status: :see_other
  end

  # A model refusal on a closed event, raised by a writer, lands on the page
  # with the model's message.
  def event_closed(error)
    redirect_to scoped_path, alert: error.message, status: :see_other
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

  # The organizer hears how many guests a notice reached: " N guests
  # emailed." and, when the cap or the cooldown skipped some, how long to
  # wait. Leading space so it appends to a flash that already says what
  # was saved.
  def notice_report(result)
    sent = result.fetch(:sent)
    skipped = result.fetch(:skipped)
    report = " #{sent} #{'guest'.pluralize(sent)} emailed."
    report += " #{skipped} skipped (recently notified). Try again after 10 minutes." if skipped.positive?
    report
  end

  def forbid_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def render_link_not_found
    render "participations/not_found", status: :not_found
  end
end
