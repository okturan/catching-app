# One row per transactional mail: written when the mail is enqueued, updated
# when it is delivered or fails. It is the source for every send cap and for
# the organizer table's delivery state, and it survives participant removal.
class MailDelivery < ApplicationRecord
  KINDS = %w[organizer_link invitation response_confirmation finalized link_shown event_updated cancelled reopened].freeze
  DOT_INSENSITIVE_DOMAINS = %w[gmail.com googlemail.com].freeze

  class CapExceeded < Refusal; end

  belongs_to :event
  belongs_to :participant, optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true

  # The organizer who sent it, as the cap key; queries normalize the same way.
  normalizes :sender_email, with: -> { canonical(it) }
  before_validation { self.canonical_recipient_email = self.class.canonical(recipient_email) }

  validates :recipient_email, presence: true

  scope :since, ->(time) { where(created_at: time..) }

  # Every transactional mail starts here: its ledger row, then the job that
  # sends it. The params after the recipient ride along to ParticipantMailer.
  def self.deliver_later(kind, to:, token: nil, sender: nil, request_ip: nil, **params)
    record!(kind, to:, sender:, request_ip:).tap do |delivery|
      ParticipantMailer.with(delivery:, token:, **params).public_send(kind).deliver_later
    end
  end

  # A row with no mail behind it, such as a link shown to copy.
  def self.record!(kind, to:, sender: nil, request_ip: nil)
    create!(event: to.event, participant: to, kind:, recipient_email: to.email, sender_email: sender&.email, request_ip:)
  end

  # Cap key: plus-tags stripped; dots removed for Gmail. Plus-addressing must
  # not buy a fresh allowance.
  def self.canonical(email)
    local, domain = email.to_s.strip.downcase.split("@", 2)
    return email.to_s.strip.downcase if local.blank? || domain.blank?

    local = local.split("+", 2).first
    local = local.delete(".") if DOT_INSENSITIVE_DOMAINS.include?(domain)
    "#{local}@#{domain}"
  end

  def state
    return :failed if failed_at
    return :delivered if delivered_at
    created_at < 15.minutes.ago ? :unknown : :queued
  end
end
