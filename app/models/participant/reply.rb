# A guest's answer: painted times, "none of these work", or leaving for good.
module Participant::Reply
  extend ActiveSupport::Concern

  included do
    # Replied, and not declined, left or voided.
    scope :counting, -> { where.not(responded_at: nil).where(declined_at: nil, left_at: nil, reply_voided_at: nil) }
  end

  def counting?
    responded_at? && !declined_at? && !left_at? && !voided?
  end

  def voided?
    reply_voided_at?
  end

  def replied_before_revision?
    responded_at? && event.offer_revised_at? && responded_at < event.offer_revised_at
  end

  def replied_before_reopen?
    responded_at? && event.reopened_at? && responded_at < event.reopened_at
  end

  # The first answer is confirmed by mail.
  def reply!(starts_at, details = {})
    first_reply = !responded_at?
    event.with_lock do
      event.replace_time_slots!(participant: self, starts_at:)
      record_answer!(details, declined_at: nil)
    end
    MailDelivery.deliver_later(:response_confirmation, to: self) if first_reply
  end

  # "None of these times work": out of consensus, link kept.
  def decline!(details = {})
    first_reply = !responded_at?
    event.with_lock do
      event.ensure_open!
      time_slots.delete_all
      record_answer!(details, declined_at: Time.current)
    end
    MailDelivery.deliver_later(:response_confirmation, to: self) if first_reply
  end

  # For good: slots, both credentials and the claim go.
  def leave!
    event.with_lock do
      time_slots.delete_all
      now = Time.current
      reload.update!(responded_at: now, declined_at: now, left_at: now, reply_voided_at: nil, user_id: nil,
        token_digest: nil, pending_token_digest: nil, pending_token_expires_at: nil)
    end
  end

  private

  # Reloaded under the lock: an offer revision may have voided this guest
  # since it was read, and answering clears that.
  def record_answer!(details, declined_at:)
    reload.update!(details.to_h.compact_blank.merge(responded_at: Time.current, declined_at:, reply_voided_at: nil))
  end
end
