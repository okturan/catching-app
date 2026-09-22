# Someone taking part in an event: its one organizer or a guest. Everyone is
# reached through a capability link; an account only remembers events.
class Participant < ApplicationRecord
  include Tokens, Reply

  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  belongs_to :event
  belongs_to :user, optional: true
  has_many :time_slots, dependent: :delete_all
  has_many :mail_deliveries

  enum :role, { organizer: "organizer", guest: "guest" }, validate: true

  normalizes :email, with: -> { it.strip.downcase }
  normalizes :name, with: -> { it.squish.presence }

  validates :email, presence: true, length: { maximum: 254 }, format: { with: EMAIL_FORMAT, allow_blank: true }, uniqueness: { scope: :event_id }
  validates :name, length: { maximum: 100 }
  validates :name, presence: true, if: :organizer?
  validates :time_zone, time_zone: true, allow_nil: true

  scope :active, -> { where(left_at: nil) }
  scope :linked, -> { where.not(token_digest: nil) }
  scope :unsent, -> { guest.active.where(token_digest: nil) }

  # The addresses in an "Invite people" box: split on commas and new lines,
  # normalized and deduplicated. A bad address names itself.
  def self.addresses_from(text)
    raise Refusal, "The invitation list is too long" if text.bytesize > 4.kilobytes

    addresses = text.split(/[\n,]/).filter_map { normalize_value_for(:email, it).presence }.uniq
    invalid = addresses.find { !it.match?(EMAIL_FORMAT) || it.length > 254 }
    raise Refusal, "#{invalid} is not a valid email address" if invalid

    addresses
  end

  # When this participant can meet, earliest first: the organizer's offer or
  # a guest's picks.
  def available_start_times
    time_slots.order(:start_time).pluck(:start_time)
  end

  def claimed?
    user_id?
  end

  def left?
    left_at?
  end

  # The name other participants see: an address is never shown to guests.
  def display_name
    name || "Guest"
  end
end
