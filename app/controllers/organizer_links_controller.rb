# Lost-link recovery. The response is constant whatever the address is.
class OrganizerLinksController < ApplicationController
  NOTICE = "If that address organizes an event, we sent it a new link.".freeze

  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create

  def new
  end

  def create
    email = Participant.normalize_value_for(:email, params.dig(:organizer_link, :email).to_s)
    if email.match?(Participant::EMAIL_FORMAT) && MailDelivery::Caps.organizer_link_allowed?(email)
      Participant.organizer.active.where(email:).joins(:event).merge(Event.not_cancelled).includes(:event).each do |organizer|
        organizer.send_organizer_link!(request_ip: request.remote_ip, pending: true)
      end
    end

    redirect_to new_organizer_link_path, notice: NOTICE, status: :see_other
  end
end
