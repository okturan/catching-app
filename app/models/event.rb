class Event < ApplicationRecord
  class ClosedError < StandardError; end

  SLOT_MINUTES = [ 15, 30, 60 ].freeze

  has_many :participants, dependent: :destroy, inverse_of: :event
  has_one :organizer, -> { organizer }, class_name: "Participant", inverse_of: :event
  has_many :guests, -> { guest }, class_name: "Participant", inverse_of: :event
  has_many :activities, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :event
  has_many :time_slots, dependent: :delete_all, inverse_of: :event
  has_many :mail_deliveries, dependent: :delete_all, inverse_of: :event

  normalizes :name, with: ->(name) { name.squish }
  normalizes :description, with: ->(description) { description.strip }

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, presence: true, length: { maximum: 2000 }
  validates :slot_minutes, inclusion: { in: SLOT_MINUTES }
  validates :start_time, :end_time, presence: true, if: :status?
  validate :time_zone_is_known
  validate :end_time_follows_start_time
  validate :grid_is_frozen_after_replies, on: :update

  scope :for_user, ->(user) {
    joins(:participants).merge(Participant.active).where(participants: { user_id: user.id }).distinct
  }
  scope :organized_by, ->(user) {
    joins(:participants).merge(Participant.active.organizer).where(participants: { user_id: user.id }).distinct
  }

  # The only creation path: event, organizer, offer and guest rows in one
  # transaction. Invitee emails are already parsed and normalized.
  def self.plan!(attributes:, organizer:, starts_at:, invitee_emails: [])
    transaction do
      event = create!(attributes)
      organizer_row = event.participants.create!(
        role: :organizer,
        email: organizer.fetch(:email),
        name: organizer.fetch(:name),
        user: organizer[:user],
        responded_at: Time.current
      )
      event.replace_time_slots!(participant: organizer_row, starts_at: starts_at)
      invitee_emails.uniq.each do |email|
        next if email == organizer_row.email

        event.participants.create!(role: :guest, email: email)
      end
      event
    end
  end

  def slot_length
    slot_minutes.minutes
  end

  def replace_time_slots!(participant:, starts_at:)
    raise ArgumentError, "Select at least one time slot" if starts_at.blank? || starts_at.any?(&:nil?)
    raise ArgumentError, "Participant belongs to another event" unless participant.event_id == id

    with_lock do
      ensure_pending!
      ensure_aligned!(starts_at)
      ensure_slots_were_offered!(participant, starts_at)

      time_slots.where(participant_id: participant.id).delete_all
      now = Time.current
      rows = starts_at.uniq.map do |start_time|
        { participant_id: participant.id, event_id: id, start_time: start_time, created_at: now, updated_at: now }
      end
      TimeSlot.insert_all!(rows)
    end
  end

  # "None of these times work": slots cleared, excluded from consensus, link kept.
  def mark_unavailable!(participant:)
    with_lock do
      ensure_pending!
      now = Time.current
      time_slots.where(participant_id: participant.id).delete_all
      participant.update!(responded_at: now, declined_at: now)
    end
  end

  def finalize!(starts_at:)
    selected_slots = starts_at.uniq.sort

    with_lock do
      ensure_pending!
      ensure_replies!
      ensure_consensus!(selected_slots)
      ensure_contiguous!(selected_slots)

      update!(
        start_time: selected_slots.min,
        end_time: selected_slots.max + slot_length,
        status: true
      )
    end
  end

  # Start times shared by every counting participant, in one statement: the
  # numerator is limited to counting rows, the denominator is a correlated
  # count in the same snapshot, and the EXISTS clause requires at least one
  # counting guest so an organizer alone never has consensus.
  def mutually_available_start_times
    time_slots
      .where(participant_id: participants.counting.select(:id))
      .group(:start_time)
      .having(<<~SQL.squish, id: id)
        COUNT(DISTINCT participant_id) = (
          SELECT COUNT(*) FROM participants
          WHERE event_id = :id AND responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL
        )
        AND EXISTS (
          SELECT 1 FROM participants
          WHERE event_id = :id AND role = 'guest' AND responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL
        )
      SQL
      .order(:start_time)
      .pluck(:start_time)
  end

  # Every instant must sit on the grid anchored at local midnight in the
  # event zone, the same generator the JavaScript uses. Rails resolves a
  # nonexistent local midnight forward, like Luxon's startOf("day").
  def ensure_aligned!(starts_at)
    zone = ActiveSupport::TimeZone[time_zone]
    step = slot_minutes * 60
    aligned = starts_at.all? do |start_time|
      local = start_time.in_time_zone(zone)
      ((local.to_i - local.beginning_of_day.to_i) % step).zero?
    end
    return if aligned

    raise ArgumentError, "Select time slots on the event's #{slot_minutes}-minute grid"
  end

  private

  def ensure_pending!
    raise ClosedError, "Availability is closed for this event" if status?
  end

  def ensure_replies!
    return if participants.counting.guest.exists?

    raise ArgumentError, "Wait for at least one reply before confirming"
  end

  def ensure_slots_were_offered!(participant, selected_slots)
    return if participant.organizer?

    offered = time_slots.where(participant_id: organizer.id, start_time: selected_slots).pluck(:start_time)
    return if selected_slots.all? { |slot| offered.include?(slot) }

    raise ArgumentError, "Select only time slots offered by the organizer"
  end

  def ensure_consensus!(selected_slots)
    consensus_slots = mutually_available_start_times
    return if selected_slots.all? { |slot| consensus_slots.include?(slot) }

    raise ArgumentError, "Select only time slots available to every participant"
  end

  def ensure_contiguous!(selected_slots)
    contiguous = selected_slots.present? &&
      selected_slots.each_cons(2).all? { |earlier, later| later - earlier == slot_length }
    return if contiguous

    raise ArgumentError, "Select one continuous meeting window"
  end

  def time_zone_is_known
    return if time_zone.present? && ActiveSupport::TimeZone[time_zone]

    errors.add(:time_zone, "is not a known time zone")
  end

  def end_time_follows_start_time
    return if start_time.blank? || end_time.blank? || end_time > start_time

    errors.add(:end_time, "must be after the start time")
  end

  def grid_is_frozen_after_replies
    return unless slot_minutes_changed? || time_zone_changed?
    return unless participants.guest.where.not(responded_at: nil).exists?

    errors.add(:slot_minutes, "cannot change after a guest has replied") if slot_minutes_changed?
    errors.add(:time_zone, "cannot change after a guest has replied") if time_zone_changed?
  end
end
