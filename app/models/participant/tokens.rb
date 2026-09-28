# Capability links. Only digests are stored. A pending token rides in the
# newest mail beside the live one and becomes live on its first write,
# retiring the token it replaces.
module Participant::Tokens
  extend ActiveSupport::Concern

  FORMAT = /\A[A-Za-z0-9]{32}\z/

  included do
    # Found by a link, a participant's paths carry its token, so their pages
    # open without a session; otherwise they name the id.
    attr_accessor :link_token
  end

  class_methods do
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    # Strips what mail clients glue on to a link, such as a trailing "." or ")".
    def canonical_key(raw_key)
      raw_key.sub(/[^A-Za-z0-9]+\z/, "")
    end

    # A string that cannot be a token costs no query.
    def find_by_link_token(raw_token)
      token = canonical_key(raw_token)
      return unless token.match?(FORMAT)

      hashed = digest(token)
      active.where(token_digest: hashed)
        .or(active.where(pending_token_digest: hashed, pending_token_expires_at: [ nil, Time.current.. ]))
        .first&.tap { it.link_token = token }
    end
  end

  def to_param
    link_token || super
  end

  def found_by_pending_token?
    link_token.present? && pending_token_digest == self.class.digest(link_token)
  end

  def issue_live_token!
    new_token.tap { update!(token_digest: self.class.digest(it)) }
  end

  # The first link gets the live token; later ones a pending token beside it,
  # so a link sent earlier keeps working.
  def issue_token!
    token_digest? ? issue_pending_token! : issue_live_token!
  end

  def issue_pending_token!(expires_in: nil)
    new_token.tap { update!(pending_token_digest: self.class.digest(it), pending_token_expires_at: expires_in&.from_now) }
  end

  # The claim is cleared unless the account that claimed it is the one
  # promoting, so a forwarded mail cannot keep somebody else's account on.
  def promote_pending!(actor: nil)
    pending_digest = self.class.digest(link_token)
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
