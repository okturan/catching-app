# The organizer's offer and the guests' replies: painted slots on a grid
# anchored at local midnight in the event's zone.
module Event::Availability
  extend ActiveSupport::Concern

  # What revise_offer! did: the instants added and removed, the guests who
  # lost some picks (trimmed) or all of them (voided), whether the step or
  # zone moved, and whether a planned length stopped fitting and was cleared.
  Revision = Data.define(:added, :removed, :trimmed_ids, :voided_ids, :grid_changed, :duration_cleared) do
    def delta? = added.any? || removed.any?
    def no_op? = !delta? && !grid_changed

    def to_s
      if delta? then "Times updated: #{added.size} added, #{removed.size} removed."
      elsif grid_changed then "Slot length and zone updated."
      else "Nothing changed."
      end
    end
  end

  included do
    validate :grid_is_frozen_after_replies, on: :update
  end

  # Replaces one participant's painted slots: the organizer's offer when the
  # event is planned, or a guest's reply, which may use offered instants only.
  def replace_time_slots!(participant:, starts_at:)
    with_lock do
      ensure_open!
      ensure_aligned!(starts_at)
      ensure_offered!(starts_at) if participant.guest?

      time_slots.where(participant:).delete_all
      insert_slots!(participant, starts_at.uniq)
    end
  end

  # The organizer changes the offered times. The complete future offer comes
  # in; instants behind the cut-off are left alone. Guest picks at removed
  # instants go with them, so guest slots stay a subset of the offer, and a
  # guest left with nothing is voided until they reply again. Step and zone
  # may change only before the first reply. A submission that changes
  # nothing writes nothing.
  def revise_offer!(starts_at:, slot_minutes: nil, time_zone: nil)
    with_lock do
      ensure_open!
      assign_attributes({ slot_minutes:, time_zone: }.compact_blank)
      grid_changed = slot_minutes_changed? || time_zone_changed?
      duration_cleared = clear_unfitting_duration
      validate!
      ensure_aligned!(starts_at)

      added, removed = offer_changes_to(starts_at)
      if added.empty? && removed.empty?
        save_revision! if grid_changed
        next Revision.new(added:, removed:, trimmed_ids: [], voided_ids: [], grid_changed:, duration_cleared:)
      end

      organizer.time_slots.where(start_time: removed).delete_all
      insert_slots!(organizer, added)
      trimmed_ids = remove_guest_picks_at!(removed)
      voided_ids = void_emptied_replies!
      save_revision!(offer_revised_at: Time.current, offer_revision_added: added.size, offer_revision_removed: removed.size)
      Revision.new(added:, removed:, trimmed_ids: trimmed_ids - voided_ids, voided_ids:, grid_changed:, duration_cleared:)
    rescue ActiveRecord::RecordInvalid, Refusal
      # Leave the instance as it was read, so it can take the next lock.
      restore_attributes
      raise
    end
  end

  # Slot length and zone relabel every cell, so they freeze at the first reply.
  def grid_frozen?
    guests.where.not(responded_at: nil).exists?
  end

  # Every instant sits on the grid anchored at local midnight in the event's
  # zone, as the JavaScript draws it. Rails moves a nonexistent local midnight
  # forward, like Luxon's startOf("day").
  def aligned?(instants)
    zone = ActiveSupport::TimeZone[time_zone]
    instants.all? do |instant|
      local = instant.in_time_zone(zone)
      ((local.to_i - local.beginning_of_day.to_i) % (slot_minutes * 60)).zero?
    end
  end

  # The organizer offered times and every one of them is behind the cut-off:
  # nothing can be painted or set until the offer changes.
  def every_offer_past?
    organizer.time_slots.exists? && organizer.time_slots.where(start_time: TimeSlot::PAST_GRACE.ago..).none?
  end

  private

  def ensure_aligned!(starts_at)
    raise Refusal, "Select time slots on the event's #{slot_minutes}-minute grid" unless aligned?(starts_at)
  end

  # Compared as UTC Times: Array#- matches with eql?, and a TimeWithZone is
  # never eql? to a Time.
  def ensure_offered!(starts_at)
    unoffered = starts_at.map(&:getutc) - organizer.available_start_times.map(&:getutc)
    raise Refusal, "Select only time slots offered by the organizer" if unoffered.any?
  end

  def insert_slots!(participant, instants)
    TimeSlot.insert_all!(instants.map { { participant_id: participant.id, event_id: id, start_time: it } }) if instants.any?
  end

  # UTC Times on both sides, as in ensure_offered!.
  def offer_changes_to(starts_at)
    cutoff = TimeSlot::PAST_GRACE.ago
    current = organizer.time_slots.where(start_time: cutoff..).pluck(:start_time).map(&:getutc)
    wanted = starts_at.map(&:getutc).uniq.select { it >= cutoff }
    [ wanted - current, current - wanted ]
  end

  # Returns the guests who lost a pick.
  def remove_guest_picks_at!(removed)
    picks = time_slots.where(start_time: removed).where.not(participant: organizer)
    picks.distinct.pluck(:participant_id).tap { picks.delete_all }
  end

  # A reply left with nothing is voided, not reset: it stays on record but no
  # longer counts until the guest saves again. Returns the voided guests.
  def void_emptied_replies!
    emptied = guests.counting.where.not(id: time_slots.select(:participant_id)).pluck(:id)
    guests.where(id: emptied).update_all(reply_voided_at: Time.current, updated_at: Time.current) if emptied.any?
    emptied
  end

  def save_revision!(attributes = {})
    update!(**attributes, revision: revision + 1)
  end

  # A planned length is a hint, so a step change that leaves it off the grid
  # clears it rather than refusing. True when cleared.
  def clear_unfitting_duration
    return false unless slot_minutes_changed? && duration_minutes && Event::SLOT_MINUTES.include?(slot_minutes)
    return false if (duration_minutes % slot_minutes).zero?

    self.duration_minutes = nil
    true
  end

  def grid_is_frozen_after_replies
    return unless (slot_minutes_changed? || time_zone_changed?) && grid_frozen?

    errors.add(:slot_minutes, "cannot change after a guest has replied") if slot_minutes_changed?
    errors.add(:time_zone, "cannot change after a guest has replied") if time_zone_changed?
  end
end
