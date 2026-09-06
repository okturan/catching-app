class Event < ApplicationRecord
  class ClosedError < StandardError; end

  SLOT_MINUTES = [ 15, 30, 60 ].freeze
  MAX_DURATION_MINUTES = 1440
  WEB_ADDRESS_MESSAGE = "must be a web address starting with http:// or https://".freeze
  # The fields an organizer edits on the details page; changing any of them
  # is a new revision of what guests see.
  DETAIL_ATTRIBUTES = %w[name description place place_url duration_minutes].freeze

  has_many :participants, dependent: :destroy, inverse_of: :event
  has_one :organizer, -> { organizer }, class_name: "Participant", inverse_of: :event
  has_many :guests, -> { guest }, class_name: "Participant", inverse_of: :event
  has_many :activities, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :event
  has_many :time_slots, dependent: :delete_all, inverse_of: :event
  has_many :mail_deliveries, dependent: :delete_all, inverse_of: :event

  normalizes :name, with: ->(name) { name.squish }
  normalizes :description, with: ->(description) { description.strip }
  normalizes :place, with: ->(place) { place.squish.presence }
  # Strip, then downcase the scheme only: "HTTPS://Zoom.us/J/1" keeps its path.
  normalizes :place_url, with: ->(url) {
    stripped = url.strip
    stripped.presence && stripped.sub(/\A[a-z][a-z0-9+.\-]*(?=:)/i, &:downcase)
  }

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, presence: true, length: { maximum: 2000 }
  validates :place, length: { maximum: 200 }
  validates :slot_minutes, inclusion: { in: SLOT_MINUTES }
  validates :duration_minutes, numericality: { only_integer: true }, allow_nil: true
  validates :start_time, :end_time, presence: true, if: :status?
  validate :time_zone_is_known
  validate :place_url_is_a_web_address
  validate :duration_is_whole_slots
  validate :end_time_follows_start_time
  validate :grid_is_frozen_after_replies, on: :update
  validate :cancellation_is_final, on: :update

  scope :for_user, ->(user) {
    joins(:participants).merge(Participant.active).where(participants: { user_id: user.id }).distinct
  }
  scope :organized_by, ->(user) {
    joins(:participants).merge(Participant.active.organizer).where(participants: { user_id: user.id }).distinct
  }
  scope :not_cancelled, -> { where(cancelled_at: nil) }

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

  # Three states. Open: still planning, everything works. Finalized: the
  # time is set, availability is closed. Cancelled: terminal, read-only but
  # for Leave and Claim; a finalized event keeps its window when cancelled.
  def cancelled?
    cancelled_at.present?
  end

  def open?
    !status? && !cancelled?
  end

  def closed?
    status? || cancelled?
  end

  # The organizer calls it off. Nothing is deleted and nothing else changes:
  # tokens, claims, slots, the plan and a set window all stay, so every link
  # keeps opening a page that says so.
  def cancel!
    with_lock do
      ensure_not_cancelled!
      update!(cancelled_at: Time.current, revision: revision + 1)
    end
  end

  # The organizer's details edit: one locked save. Only a change to a field
  # guests can see bumps the revision, so a no-op leaves the row untouched.
  # Returns the change set (attribute => [old, new]) without the bookkeeping.
  def update_details!(attributes)
    with_lock do
      ensure_not_cancelled!
      assign_attributes(attributes)
      self.revision += 1 if changed.intersect?(DETAIL_ATTRIBUTES)
      save!
      saved_changes.except("revision", "updated_at")
    end
  end

  # Plan writes: one lock each, refused once cancelled, and a revision bump
  # so guests and calendar files see a new SEQUENCE. None of them mails
  # anyone; the organizer tells the guests afterwards.
  def add_plan_item!(attributes)
    revise_plan! do
      activities.create!(attributes.to_h.merge(position: (activities.maximum(:position) || -1) + 1))
    end
  end

  def update_plan_item!(item, attributes)
    revise_plan! { item.update!(attributes) }
  end

  def remove_plan_item!(item)
    revise_plan! { item.destroy! }
  end

  # One write per rearrangement: the plan is renumbered densely from its
  # (position, id) order, then the item lands at the target index, clamped
  # to the plan. A target equal to the current index changes nothing.
  def move_plan_item!(item, position)
    with_lock do
      ensure_not_cancelled!
      items = activities.reload.to_a
      renumber_plan!(items)
      from = items.index(item) or raise ActiveRecord::RecordNotFound
      target = position.clamp(0, items.size - 1)
      next if from == target

      items.insert(target, items.delete_at(from))
      renumber_plan!(items)
      increment!(:revision)
    end
  end

  # Each item with its derived start: start_time plus the lengths of every
  # item before it. Starts exist only once the time is set and the event is
  # not cancelled, and stop after the first item without a length. A mailer
  # passes the start it was handed (from:) so a retried job never reads the row.
  def plan_timeline(from: nil)
    cursor = from || (status? && !cancelled? ? start_time : nil)
    activities.map do |activity|
      start = cursor
      cursor = cursor && activity.duration ? cursor + activity.duration.minutes : nil
      [ activity, start ]
    end
  end

  def plan_minutes
    activities.sum { |activity| activity.duration.to_i }
  end

  def window_minutes
    return nil unless status? && start_time && end_time

    ((end_time - start_time) / 60).to_i
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

  # Sets the time. The revision bump makes the calendar file published by
  # the finalized mail outrank any earlier file for the same event.
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
        status: true,
        revision: revision + 1
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

  def revise_plan!
    with_lock do
      ensure_not_cancelled!
      result = yield
      increment!(:revision)
      result
    end
  end

  def renumber_plan!(items)
    items.each_with_index do |activity, index|
      activity.update_columns(position: index) unless activity.position == index
    end
  end

  # Cancelled wins over finalized: a cancelled event has one message.
  def ensure_pending!
    ensure_not_cancelled!
    raise ClosedError, "Availability is closed for this event" if status?
  end

  def ensure_not_cancelled!
    raise ClosedError, "This event was cancelled" if cancelled?
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

  # http(s), a host, no userinfo: the same shape the database check pins.
  def place_url_is_a_web_address
    return if place_url.nil?

    uri = URI.parse(place_url)
    return if %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && place_url.length <= 2000

    errors.add(:place_url, WEB_ADDRESS_MESSAGE)
  rescue URI::InvalidURIError
    errors.add(:place_url, WEB_ADDRESS_MESSAGE)
  end

  def duration_is_whole_slots
    return if duration_minutes.nil? || errors[:duration_minutes].any?

    if duration_minutes <= 0
      errors.add(:duration_minutes, "must be greater than 0")
    elsif duration_minutes > MAX_DURATION_MINUTES
      errors.add(:duration_minutes, "must be at most 24 hours")
    elsif slot_minutes.to_i.positive? && (duration_minutes % slot_minutes).nonzero?
      errors.add(:duration_minutes, "must be a whole number of #{slot_minutes}-minute slots")
    end
  end

  def end_time_follows_start_time
    return if start_time.blank? || end_time.blank? || end_time > start_time

    errors.add(:end_time, "must be after the start time")
  end

  def cancellation_is_final
    return unless cancelled_at_changed? && cancelled_at_was.present?

    errors.add(:cancelled_at, "cannot be changed once cancelled")
  end

  def grid_is_frozen_after_replies
    return unless slot_minutes_changed? || time_zone_changed?
    return unless participants.guest.where.not(responded_at: nil).exists?

    errors.add(:slot_minutes, "cannot change after a guest has replied") if slot_minutes_changed?
    errors.add(:time_zone, "cannot change after a guest has replied") if time_zone_changed?
  end
end
