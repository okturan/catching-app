# One RFC 5545 file for one event, written by hand: no gem, no dependency.
#
# Two modes. Page mode is what a participant downloads from their own page
# and may carry the join link (URL) and the event description. Mail mode is
# the attachment: names pass through mail_safe, and neither the description
# nor any URL travels, so a mail never carries an organizer-supplied link.
# Neither mode carries a capability token or an ORGANIZER property.
#
# The window is passed by the mailers (amendment 2) so a job retried after
# a reopen still renders what was set; the page passes nothing and the
# event's own window is used. STATUS follows the event unless the caller
# says otherwise (the reopened mail withdraws a window that is not cancelled).
class CalendarFile
  include EventsHelper
  include MailTextHelper

  MODES = %i[page mail].freeze
  STATUSES = { confirmed: "CONFIRMED", cancelled: "CANCELLED" }.freeze
  PRODID = "-//Catching App//EN".freeze
  ALARM_TRIGGER = "-PT15M".freeze
  CREDIT = "Planned with Catching App".freeze
  FOLD_OCTETS = 75
  CRLF = "\r\n".freeze
  ESCAPES = { "\\" => "\\\\", ";" => "\\;", "," => "\\,", "\n" => "\\n" }.freeze

  attr_reader :event, :mode, :window, :status

  def initialize(event, mode:, window: nil, status: nil)
    raise ArgumentError, "mode must be :page or :mail" unless MODES.include?(mode)

    @event = event
    @mode = mode
    @window = window || [ event.start_time, event.end_time ]
    raise ArgumentError, "a set time is needed for a calendar file" if @window.compact.size != 2

    @status = status || (event.cancelled? ? :cancelled : :confirmed)
    raise ArgumentError, "status must be :confirmed or :cancelled" unless STATUSES.key?(@status)
  end

  def body
    lines.flat_map { |line| fold(line) }.join(CRLF) + CRLF
  end

  alias to_s body

  # Stable for the life of the event and not guessable from a neighbour's.
  def uid
    "#{Digest::SHA256.hexdigest("#{event.id}:#{event.created_at.to_i}")[0, 32]}@#{host}"
  end

  private

  def lines
    start_time, end_time = window
    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:#{PRODID}",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{uid}",
      "DTSTAMP:#{utc(Time.current)}",
      "SEQUENCE:#{event.revision}",
      "DTSTART:#{utc(start_time)}",
      "DTEND:#{utc(end_time)}",
      "SUMMARY:#{escape(name)}",
      (place.present? ? "LOCATION:#{escape(place)}" : nil),
      (page? && event.place_url.present? ? "URL:#{event.place_url}" : nil),
      "STATUS:#{STATUSES.fetch(status)}",
      "DESCRIPTION:#{escape(description)}",
      "BEGIN:VALARM",
      "ACTION:DISPLAY",
      "DESCRIPTION:#{escape(name)}",
      "TRIGGER:#{ALARM_TRIGGER}",
      "END:VALARM",
      "END:VEVENT",
      "END:VCALENDAR"
    ].compact
  end

  def page?
    mode == :page
  end

  def name
    text(event.name)
  end

  def place
    text(event.place)
  end

  # Page mode: the event's own words first, then the plan, then the credit.
  # Mail mode: the plan and the credit only.
  def description
    paragraphs = []
    paragraphs << event.description.to_s.strip if page? && event.description.present?
    plan_lines = event.activities.each_with_index.map do |activity, index|
      length = activity.duration ? " (#{duration_label(activity.duration)})" : ""
      "#{index + 1}. #{text(activity.name)}#{length}"
    end
    paragraphs << plan_lines.join("\n") if plan_lines.any?
    paragraphs << CREDIT
    paragraphs.join("\n\n")
  end

  # Organizer text reaches a mail only through mail_safe; the page shows the
  # same words the reader already sees.
  def text(value)
    page? ? value.to_s : mail_safe(value)
  end

  def host
    Rails.application.config.action_mailer.default_url_options&.dig(:host) || "catching.app"
  end

  def utc(instant)
    instant.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  # TEXT values: the four characters RFC 5545 reserves, replaced literally.
  def escape(value)
    value.to_s.gsub("\r\n", "\n").gsub(/[\\;,\n]/, ESCAPES)
  end

  # Content lines longer than 75 octets continue on the next line after a
  # single space; the break falls between characters, never inside a
  # multi-byte sequence, so unfolding restores the original line.
  def fold(line)
    return [ line ] if line.bytesize <= FOLD_OCTETS

    folded = []
    current = +""
    line.each_char do |char|
      if current.bytesize + char.bytesize > FOLD_OCTETS
        folded << current
        current = +" "
      end
      current << char
    end
    folded << current
  end
end
