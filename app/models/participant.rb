class Participant < ApplicationRecord
  TOKEN_FORMAT = /\A[A-Za-z0-9]{32}\z/
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  # Result of resolving a raw capability token.
  TokenResolution = Data.define(:participant, :via_pending, :canonical_token)

  belongs_to :event, inverse_of: :participants
  belongs_to :user, optional: true, inverse_of: :participants

  has_many :time_slots, dependent: :delete_all, inverse_of: :participant
  has_many :mail_deliveries, dependent: :nullify, inverse_of: :participant

  enum :role, { organizer: "organizer", guest: "guest" }, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.squish.presence }

  validates :email, presence: true, length: { maximum: 254 }, format: { with: EMAIL_FORMAT },
    uniqueness: { scope: :event_id }
  validates :name, length: { maximum: 100 }
  validates :name, presence: true, if: :organizer?
  validate :time_zone_is_known

  scope :active, -> { where(left_at: nil) }
  scope :counting, -> { where.not(responded_at: nil).where(declined_at: nil, left_at: nil) }
  scope :linked, -> { where.not(token_digest: nil) }
  scope :unsent, -> { guest.active.where(token_digest: nil) }

  class << self
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    # Strips mail-client suffixes such as a trailing "." or ")".
    def canonical_token(raw_token)
      raw_token.to_s.sub(/[^A-Za-z0-9]+\z/, "")
    end

    # Resolves a raw token without a query when it cannot be a token. A pending
    # token resolves the participant but changes nothing: promotion happens on
    # the first write, see #promote_pending!.
    def resolve_token(raw_token)
      canonical = canonical_token(raw_token)
      return nil unless canonical.match?(TOKEN_FORMAT)

      hashed = digest(canonical)
      participant = active.where(token_digest: hashed)
        .or(active.where(pending_token_digest: hashed)
          .where("pending_token_expires_at IS NULL OR pending_token_expires_at > ?", Time.current))
        .first
      return nil unless participant

      TokenResolution.new(
        participant: participant,
        via_pending: participant.pending_token_digest == hashed,
        canonical_token: canonical
      )
    end

    def find_by_token(raw_token)
      resolve_token(raw_token)&.participant
    end

    def find_by_token!(raw_token)
      find_by_token(raw_token) or raise ActiveRecord::RecordNotFound.new("participant not found", name)
    end
  end

  def counting?
    responded_at.present? && declined_at.nil? && left_at.nil?
  end

  def left?
    left_at.present?
  end

  def claimed?
    user_id.present?
  end

  # The name as another participant should see it.
  def display_name(viewer_role: :guest)
    return name if name.present?

    viewer_role.to_s == "organizer" ? email : "Guest"
  end

  def issue_live_token!
    raise ArgumentError, "cannot issue a token for a participant who left" if left?

    raw = SecureRandom.base58(32)
    update!(token_digest: self.class.digest(raw))
    raw
  end

  # Guests receive pending tokens without expiry; organizer recovery passes
  # expires_in: 24.hours. The live token and the claim are untouched.
  def issue_pending_token!(expires_in: nil)
    raise ArgumentError, "cannot issue a token for a participant who left" if left?

    raw = SecureRandom.base58(32)
    update!(
      pending_token_digest: self.class.digest(raw),
      pending_token_expires_at: expires_in && expires_in.from_now
    )
    raw
  end

  # Makes a pending token live in one guarded statement. The claim is cleared
  # unless the actor is the claiming user, so a forwarded resend cannot keep
  # somebody else's account attached.
  def promote_pending!(pending_digest, actor: nil)
    changes = {
      token_digest: pending_digest,
      pending_token_digest: nil,
      pending_token_expires_at: nil,
      updated_at: Time.current
    }
    changes[:user_id] = nil unless actor && user_id && actor.id == user_id

    promoted = self.class.where(id: id, pending_token_digest: pending_digest).update_all(changes)
    reload
    promoted == 1
  end

  def revoke_tokens!
    update!(token_digest: nil, pending_token_digest: nil, pending_token_expires_at: nil)
  end

  # The guest's kill switch: slots gone, both credentials gone, claim gone.
  def leave!
    raise ArgumentError, "only guests can leave" unless guest?

    event.with_lock do
      now = Time.current
      time_slots.delete_all
      update!(
        responded_at: now, declined_at: now, left_at: now, user_id: nil,
        token_digest: nil, pending_token_digest: nil, pending_token_expires_at: nil
      )
    end
  end

  private

  def time_zone_is_known
    return if time_zone.nil? || ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, "is not a known time zone")
  end
end
