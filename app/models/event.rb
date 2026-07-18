class Event < ApplicationRecord
  class ClosedError < StandardError; end

  belongs_to :user, inverse_of: :events

  has_many :activities, dependent: :destroy, inverse_of: :event
  has_many :time_slots, dependent: :destroy, inverse_of: :event
  has_many :user_events, dependent: :destroy, inverse_of: :event
  has_many :invited_users, through: :user_events, source: :user

  validates :name, :description, presence: true
  validates :start_time, :end_time, presence: true, if: :status?
  validate :end_time_follows_start_time

  scope :accessible_to, ->(user) {
    left_outer_joins(:user_events)
      .where("events.user_id = :user_id OR user_events.user_id = :user_id", user_id: user.id)
      .distinct
  }

  def replace_time_slots!(user:, starts_at:)
    with_lock do
      ensure_pending!
      ensure_slots_were_offered!(user, starts_at)

      time_slots.where(user: user).delete_all
      starts_at.each { |start_time| time_slots.create!(user: user, start_time: start_time) }
    end
  end

  def finalize!(starts_at:)
    selected_slots = starts_at.uniq.sort

    with_lock do
      ensure_pending!
      ensure_consensus!(selected_slots)
      ensure_contiguous!(selected_slots)

      update!(
        start_time: selected_slots.min,
        end_time: selected_slots.max + 1.hour,
        status: true
      )
    end
  end

  def mutually_available_start_times
    participant_ids = [ user_id, *invited_user_ids ]

    time_slots
      .where(user_id: participant_ids)
      .group(:start_time)
      .having("COUNT(DISTINCT user_id) = ?", participant_ids.size)
      .order(:start_time)
      .pluck(:start_time)
  end

  private

  def ensure_pending!
    raise ClosedError, "Availability is closed for this event" if status?
  end

  def ensure_slots_were_offered!(participant, selected_slots)
    return if participant == user

    offered_slots = time_slots.where(user: user, start_time: selected_slots).pluck(:start_time)
    return if selected_slots.all? { |slot| offered_slots.include?(slot) }

    raise ArgumentError, "Select only time slots offered by the organizer"
  end

  def ensure_consensus!(selected_slots)
    consensus_slots = mutually_available_start_times
    return if selected_slots.all? { |slot| consensus_slots.include?(slot) }

    raise ArgumentError, "Select only time slots available to every participant"
  end

  def ensure_contiguous!(selected_slots)
    return if selected_slots.present? && selected_slots.each_cons(2).all? { |earlier, later| later - earlier == 1.hour }

    raise ArgumentError, "Select one continuous meeting window"
  end

  def end_time_follows_start_time
    return if start_time.blank? || end_time.blank? || end_time > start_time

    errors.add(:end_time, "must be after the start time")
  end
end
