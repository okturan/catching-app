# Setting the time from the consensus, and taking it back. An event is
# finalized exactly when it has a window.
module Event::Finalization
  extend ActiveSupport::Concern

  REOPEN_LIMIT = 2
  REOPEN_LIMIT_MESSAGE = "This event was reopened twice already. Cancel it and plan a new one.".freeze

  included do
    scope :finalized, -> { where.not(start_time: nil) }

    validates :end_time, comparison: { greater_than: :start_time, message: "must be after the start time" }, if: :start_time?
  end

  def finalized?
    start_time?
  end

  # Sets the time: one continuous window of slots every counting participant
  # shares, once at least one guest has replied.
  def finalize!(starts_at:)
    window = starts_at.uniq.sort

    with_lock do
      ensure_open!
      ensure_replies!
      ensure_consensus!(window)
      ensure_contiguous!(window)

      update!(start_time: window.first, end_time: window.last + slot_length, revision: revision + 1)
    end
  end

  # Withdraws the set time. The event plans again with every pick, reply,
  # token and claim intact. Returns the withdrawn window, so the reopened mail
  # can print it and clear the calendar entry.
  def reopen!
    with_lock do
      ensure_not_cancelled!
      raise Refusal, "Only a set time can be reopened" unless finalized?
      raise Refusal, REOPEN_LIMIT_MESSAGE if reopen_count >= REOPEN_LIMIT

      window = [ start_time, end_time ]
      update!(start_time: nil, end_time: nil, reopened_at: Time.current, reopen_count: reopen_count + 1, revision: revision + 1)
      window
    end
  end

  # Start times every counting participant shares, in one statement so the
  # count it is measured against comes from the same snapshot. At least one
  # counting guest is required: an organizer alone never has consensus.
  def mutually_available_start_times
    counting = participants.counting

    time_slots
      .where(participant: counting)
      .group(:start_time)
      .having("COUNT(DISTINCT participant_id) = (#{counting.select("COUNT(*)").to_sql})")
      .having(counting.guest.arel.exists)
      .order(:start_time)
      .pluck(:start_time)
  end

  def window_minutes
    ((end_time - start_time) / 60).to_i if finalized?
  end

  private

  def ensure_replies!
    raise Refusal, "Wait for at least one reply before confirming" unless participants.counting.guest.exists?
  end

  # Compared as UTC Times, as in Availability.
  def ensure_consensus!(window)
    unshared = window.map(&:getutc) - mutually_available_start_times.map(&:getutc)
    raise Refusal, "Select only time slots available to every participant" if unshared.any?
  end

  def ensure_contiguous!(window)
    contiguous = window.any? && window.each_cons(2).all? { |earlier, later| later - earlier == slot_length }
    raise Refusal, "Select one continuous meeting window" unless contiguous
  end
end
