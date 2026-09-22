# One RFC 5545 file for one event, written by hand. The page's file may carry
# the join link and the description; a mail's attachment carries neither, so
# a mail never carries an organizer-supplied link. Mailers pass the window
# and sequence they were queued with.
class CalendarFile
  STATUSES = { confirmed: "CONFIRMED", cancelled: "CANCELLED" }.freeze
  PRODID = "-//Catching App//EN".freeze
  ALARM_TRIGGER = "-PT15M".freeze
  CREDIT = "Planned with Catching App".freeze
  FOLD_OCTETS = 75
  CRLF = "\r\n".freeze
  ESCAPES = { "\\" => "\\\\", ";" => "\\;", "," => "\\,", "\n" => "\\n" }.freeze

  attr_reader :event, :mode, :window, :status, :sequence

  def initialize(event, mode:, window: nil, status: nil, sequence: nil)
    @event = event
    @mode = mode
    @window = window || [ event.start_time, event.end_time ]
    @status = status || (event.cancelled? ? :cancelled : :confirmed)
    @sequence = sequence || event.revision
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
      "SEQUENCE:#{sequence}",
      "DTSTART:#{utc(start_time)}",
      "DTEND:#{utc(end_time)}",
      "SUMMARY:#{escape(name)}",
      ("LOCATION:#{escape(place)}" if place.present?),
      ("URL:#{event.place_url}" if page? && event.place_url.present?),
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

  def description
    paragraphs = []
    paragraphs << event.description if page? && event.description.present?
    plan_lines = event.plan_items.each_with_index.map do |item, index|
      "#{index + 1}. #{text(item.name)}#{" (#{item.length})" if item.length}"
    end
    paragraphs << plan_lines.join("\n") if plan_lines.any?
    paragraphs << CREDIT
    paragraphs.join("\n\n")
  end

  def text(value)
    page? ? value.to_s : MailTextHelper.mail_safe(value)
  end

  def host
    Rails.application.config.action_mailer.default_url_options.fetch(:host)
  end

  def utc(instant)
    instant.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  # TEXT values: the four characters RFC 5545 reserves, replaced literally.
  def escape(value)
    value.to_s.gsub(/\r\n?/, "\n").gsub(/[\u0000-\u0009\u000b\u000c\u000e-\u001f\u007f]/, "").gsub(/[\\;,\n]/, ESCAPES)
  end

  # Lines over 75 octets fold between characters, never inside a multi-byte
  # sequence, so unfolding restores the original.
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
