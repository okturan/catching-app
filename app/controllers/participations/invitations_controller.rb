module Participations
  # Sends invitations to every guest without a live link, adding any new
  # addresses first. Nothing leaves before the organizer has opened the
  # emailed link.
  class InvitationsController < ParticipationScopedController
    before_action :require_opened_organizer!

    def create
      added, already = add_guests(params.dig(:invitations, :emails))
      guests = @event.participants.unsent.order(:created_at).to_a
      guests.each { Deliveries.invitation!(event: @event, guest: it, organizer: @participant, request_ip: request.remote_ip) }

      redirect_to scoped_path, notice: [
        ("#{added} added." if added.positive?),
        "#{helpers.pluralize(guests.size, "invitation")} sent.",
        ("#{already.to_sentence} already on this event." if already.any?)
      ].compact.join(" ")
    end

    private

    def add_guests(text)
      return [ 0, [] ] if text.blank?

      emails = InviteeListParser.call(text, organizer_email: @participant.email)
      already = emails & @event.participants.pluck(:email)
      fresh = emails - already
      if @event.guests.active.count + fresh.size > MailDelivery::Caps::GUESTS_PER_EVENT
        raise Refusal, "An event can have at most #{MailDelivery::Caps::GUESTS_PER_EVENT} guests"
      end

      fresh.each { @event.participants.create!(role: :guest, email: it) }
      [ fresh.size, already ]
    end
  end
end
