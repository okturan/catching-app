# A meeting to find a time for: an organizer's offer painted on a grid of
# slots, the guests' painted replies, and in time one window they all share.
#
# Open while planning, finalized once the time is set, cancelled for good.
# Every write that others can see runs under the event's row lock and bumps
# its revision, which calendar files publish as their SEQUENCE.
class Event < ApplicationRecord
  include Availability, Finalization, Cancellation, Plan, Announcements

  class Closed < Refusal; end

  SLOT_MINUTES = [ 15, 30, 60 ].freeze
  GUEST_LIMIT = 50
  # What an organizer edits on the details page; changing any of it is a new
  # revision of what guests read.
  DETAIL_ATTRIBUTES = %w[name description place place_url duration_minutes].freeze

  has_many :participants
  has_one :organizer, -> { organizer }, class_name: "Participant"
  has_many :guests, -> { guest }, class_name: "Participant"
  has_many :time_slots, dependent: :delete_all
  has_many :mail_deliveries

  normalizes :name, with: -> { it.squish }
  # Applied to nil too, so an omitted description lands on the NOT NULL column as "".
  normalizes :description, with: -> { it.to_s.strip }, apply_to_nil: true
  normalizes :place, with: -> { it.squish.presence }
  # Only the scheme is downcased: "HTTPS://Zoom.us/J/1" keeps its path.
  normalizes :place_url, with: -> { it.strip.presence&.sub(/\A[a-z][a-z0-9+.\-]*(?=:)/i, &:downcase) }

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }
  validates :place, length: { maximum: 200 }
  validates :place_url, length: { maximum: 2000 }, web_address: true, allow_nil: true
  validates :slot_minutes, inclusion: { in: SLOT_MINUTES }
  validates :time_zone, time_zone: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 24 * 60 }, allow_nil: true
  validate :duration_fits_the_grid

  # The only creation path: the event, its organizer and the offer, in one
  # transaction. Guests are invited from the organizer's page later.
  def self.plan!(attributes:, organizer:, starts_at:)
    transaction do
      create!(attributes).tap do |event|
        event.participants.organizer.create!(**organizer, responded_at: Time.current)
        event.replace_time_slots!(participant: event.organizer, starts_at:)
      end
    end
  end

  def open?
    !finalized? && !cancelled?
  end

  # The time is set and the event is still on.
  def set_in_stone?
    finalized? && !cancelled?
  end

  # Cancelled wins over finalized: a cancelled event has one message.
  def ensure_open!
    ensure_not_cancelled!
    raise Closed, "Availability is closed for this event" if finalized?
  end

  def slot_length
    slot_minutes.minutes
  end

  def planned_length
    Length.new(duration_minutes) if duration_minutes
  end

  # The organizer's details edit, in one locked save. Only a change guests
  # can see bumps the revision. Returns what changed, as attribute => [was, is].
  def update_details!(attributes)
    with_lock do
      ensure_not_cancelled!
      assign_attributes(attributes)
      self.revision += 1 if changed.intersect?(DETAIL_ATTRIBUTES)
      save!
      saved_changes.except("revision", "updated_at")
    end
  end

  # New addresses become guests without a link yet; the organizer's own is
  # left out. Returns the addresses added and those already on the event.
  def add_guests!(addresses)
    addresses -= [ organizer.email ]
    already = addresses & participants.pluck(:email)
    added = addresses - already
    raise Refusal, "An event can have at most #{GUEST_LIMIT} guests" if guests.active.count + added.size > GUEST_LIMIT

    added.each { participants.guest.create!(email: it) }
    [ added, already ]
  end

  private

  # One message per problem: an invalid length or step has said so already.
  def duration_fits_the_grid
    return if duration_minutes.nil? || errors.include?(:duration_minutes) || errors.include?(:slot_minutes)

    errors.add(:duration_minutes, "must be a whole number of #{slot_minutes}-minute slots") unless (duration_minutes % slot_minutes).zero?
  end
end
