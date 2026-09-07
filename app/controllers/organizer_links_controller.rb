# Lost-link recovery. The response is constant whatever the address is.
class OrganizerLinksController < ApplicationController
  skip_before_action :authenticate_user!

  rate_limit to: 5, within: 1.hour, only: :create

  NOTICE = "If that address organizes an event, we sent it a new link.".freeze

  def new
  end

  def create
    email = params.dig(:organizer_link, :email).to_s.strip.downcase
    if email.match?(Participant::EMAIL_FORMAT) && MailDelivery::Caps.organizer_link_allowed?(email)
      Participant.organizer.active.where(email: email).joins(:event).merge(Event.not_cancelled).find_each do |organizer|
        Deliveries.organizer_link!(event: organizer.event, organizer: organizer, request_ip: request.remote_ip, pending: true)
      end
    end

    redirect_to new_organizer_link_path, notice: NOTICE, status: :see_other
  end
end
