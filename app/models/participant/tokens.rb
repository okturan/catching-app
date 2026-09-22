# Capability links. Only digests are stored. A pending token rides in the
# newest mail beside the live one and becomes live on its first write,
# retiring the token it replaces.
module Participant::Tokens
  extend ActiveSupport::Concern

  FORMAT = /\A[A-Za-z0-9]{32}\z/

  # The participant a raw token resolves to, whether it was the pending one,
  # and the token as it should appear in a URL.
  Resolution = Data.define(:participant, :via_pending, :canonical_token)

  class_methods do
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    # Strips what mail clients glue on, such as a trailing "." or ")".
    def canonical_token(raw_token)
      raw_token.sub(/[^A-Za-z0-9]+\z/, "")
    end

    # A string that cannot be a token costs no query.
    def resolve_token(raw_token)
      canonical = canonical_token(raw_token)
      return unless canonical.match?(FORMAT)

      hashed = digest(canonical)
      participant = active.where(token_digest: hashed)
        .or(active.where(pending_token_digest: hashed, pending_token_expires_at: [ nil, Time.current.. ]))
        .first
      Resolution.new(participant:, via_pending: participant.pending_token_digest == hashed, canonical_token: canonical) if participant
    end
  end

  def issue_live_token!
    new_token.tap { update!(token_digest: self.class.digest(it)) }
  end

  # The token for a link handed out anew: the first live one, then pending
  # ones beside it, so a link sent earlier keeps working.
  def issue_token!
    token_digest? ? issue_pending_token! : issue_live_token!
  end

  # Guests' pending tokens never expire; organizer recovery passes
  # expires_in: 24.hours. The live token and the claim are untouched.
  def issue_pending_token!(expires_in: nil)
    new_token.tap { update!(pending_token_digest: self.class.digest(it), pending_token_expires_at: expires_in&.from_now) }
  end

  # Makes a pending token live in one guarded statement. The claim is cleared
  # unless the one promoting it is the account that claimed it, so a
  # forwarded mail cannot keep somebody else's account attached.
  def promote_pending!(pending_digest, actor: nil)
    promotion = { token_digest: pending_digest, pending_token_digest: nil, pending_token_expires_at: nil, updated_at: Time.current }
    promotion[:user_id] = nil unless actor && actor.id == user_id

    promoted = self.class.where(id:, pending_token_digest: pending_digest).update_all(promotion)
    reload
    promoted == 1
  end

  private

  def new_token
    SecureRandom.base58(32)
  end
end
