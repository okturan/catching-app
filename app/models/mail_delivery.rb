# One row per transactional mail: written when the mail is enqueued, updated
# when it is delivered or fails. It is the source for every send cap and for
# the organizer table's delivery state, and it survives participant removal.
class MailDelivery < ApplicationRecord
  KINDS = %w[organizer_link invitation response_confirmation finalized link_shown event_updated cancelled reopened].freeze
  DOT_INSENSITIVE_DOMAINS = %w[gmail.com googlemail.com].freeze

  class CapExceeded < StandardError; end

  belongs_to :event, inverse_of: :mail_deliveries
  belongs_to :participant, optional: true, inverse_of: :mail_deliveries

  enum :kind, KINDS.index_by(&:itself), validate: true

  before_validation :fill_canonical_recipient

  validates :recipient_email, presence: true

  scope :delivered, -> { where.not(delivered_at: nil) }
  scope :failed, -> { where.not(failed_at: nil) }
  scope :queued, -> { where(delivered_at: nil, failed_at: nil) }
  scope :since, ->(time) { where(created_at: time..) }

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

  private

  def fill_canonical_recipient
    self.canonical_recipient_email = self.class.canonical(recipient_email) if recipient_email.present?
  end
end
