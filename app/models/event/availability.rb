# The organizer's offer and the guests' replies: painted slots on a grid
# anchored at local midnight in the event's zone.
module Event::Availability
  extend ActiveSupport::Concern

  # What revise_offer! did. Trimmed guests lost some picks, voided ones all.
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

  # A guest may paint only instants the organizer offers.
  def replace_time_slots!(participant:, starts_at:)
    with_lock do
      ensure_open!
      ensure_aligned!(starts_at)
      ensure_offered!(starts_at) if participant.guest?

      time_slots.where(participant:).delete_all
      insert_slots!(participant, starts_at.uniq)
    end
  end

  # The complete future offer comes in; instants behind the cut-off are left
  # alone. Guest picks at removed instants go with them, and a guest left
  # with nothing is voided until they reply again.
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

  def grid_frozen?
    guests.where.not(responded_at: nil).exists?
  end

  # On the grid anchored at local midnight, as the JavaScript draws it. Rails
  # moves a nonexistent local midnight forward, like Luxon's startOf("day").
  def aligned?(instants)
    zone = ActiveSupport::TimeZone[time_zone]
    instants.all? do |instant|
      local = instant.in_time_zone(zone)
      ((local.to_i - local.beginning_of_day.to_i) % (slot_minutes * 60)).zero?
    end
  end

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

  def remove_guest_picks_at!(removed)
    picks = time_slots.where(start_time: removed).where.not(participant: organizer)
    picks.distinct.pluck(:participant_id).tap { picks.delete_all }
  end

  # Voided, not reset: the reply stays on record but stops counting until the
  # guest saves again.
  def void_emptied_replies!
    emptied = guests.counting.where.not(id: time_slots.select(:participant_id)).pluck(:id)
    guests.where(id: emptied).update_all(reply_voided_at: Time.current, updated_at: Time.current) if emptied.any?
    emptied
  end

  def save_revision!(attributes = {})
    update!(**attributes, revision: revision + 1)
  end

  # A planned length is a hint, so a step change clears one that stopped
  # fitting rather than refusing.
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
