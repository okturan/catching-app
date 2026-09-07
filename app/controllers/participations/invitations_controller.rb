module Participations
  # Sends invitations to every guest without a live link; optionally adds
  # more guests first. Nothing leaves before the organizer has opened the
  # emailed link.
  class InvitationsController < ParticipationScopedController
    def create
      require_opened_organizer!
      return if performed?

      notices = []
      added, skipped = add_guests(params.dig(:invitations, :emails))
      notices << "#{skipped.to_sentence} already on this event." if skipped.any?

      sent = 0
      @event.participants.unsent.order(:created_at).each do |guest|
        Deliveries.invitation!(event: @event, guest: guest, organizer: @participant, request_ip: request.remote_ip)
        sent += 1
      end

      notices.unshift("#{sent} invitation#{sent == 1 ? "" : "s"} sent.")
      notices.unshift("#{added} added.") if added.positive?
      redirect_to scoped_path, notice: notices.join(" ")
    rescue ActiveRecord::RecordInvalid, ArgumentError, MailDelivery::CapExceeded => error
      redirect_to scoped_path, alert: error.message, status: :see_other
    end

    private

    def add_guests(text)
      return [ 0, [] ] if text.blank?

      emails = InviteeListParser.call(text, organizer_email: @participant.email)
      existing = @event.participants.pluck(:email)
      skipped = emails & existing
      fresh = emails - existing
      if @event.guests.active.count + fresh.size > MailDelivery::Caps::GUESTS_PER_EVENT
        raise ArgumentError, "An event can have at most #{MailDelivery::Caps::GUESTS_PER_EVENT} guests"
      end

      fresh.each { |email| @event.participants.create!(role: :guest, email: email) }
      [ fresh.size, skipped ]
    end
  end
end
