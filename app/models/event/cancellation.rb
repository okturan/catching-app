# Calling the event off: terminal, and nothing is deleted. Tokens, claims,
# slots, the plan and a set window all stay, so every link keeps opening a
# page that says so.
module Event::Cancellation
  extend ActiveSupport::Concern

  included do
    scope :not_cancelled, -> { where(cancelled_at: nil) }
  end

  def cancelled?
    cancelled_at?
  end

  def cancel!
    with_lock do
      ensure_not_cancelled!
      update!(cancelled_at: Time.current, revision: revision + 1)
    end
  end

  def ensure_not_cancelled!
    raise Event::Closed, "This event was cancelled" if cancelled?
  end
end
