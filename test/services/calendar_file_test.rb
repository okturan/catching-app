require "test_helper"

class CalendarFileTest < ActiveSupport::TestCase
  setup do
    @event = events(:finalized)
    @event.activities.create!(name: "Pizza", duration: 30, position: 0, description: "Margherita https://evil.example/menu")
    @event.activities.create!(name: "The movie", position: 1)
    @event.update_columns(place: "Ege's place", revision: 3)
    @event.reload
  end

  def render(mode: :page, **options)
    CalendarFile.new(@event, mode: mode, **options).body
  end

  def unfold(body)
    body.gsub("\r\n ", "")
  end

  def property(body, name)
    unfold(body).split("\r\n").find { |line| line.start_with?("#{name}:") }&.delete_prefix("#{name}:")
  end

  test "every line ends with CRLF in both modes" do
    %i[page mail].each do |mode|
      body = render(mode: mode)
      assert body.end_with?("\r\n"), mode
      assert_equal body.count("\n"), body.scan("\r\n").size, "#{mode}: a bare newline slipped in"
      assert_equal body.count("\r"), body.scan("\r\n").size, "#{mode}: a bare carriage return slipped in"
    end
  end

  test "the required properties, the plan and the alarm are present exactly once" do
    body = render
    lines = unfold(body).split("\r\n")

    %w[BEGIN:VCALENDAR VERSION:2.0 PRODID:-//Catching\ App//EN METHOD:PUBLISH BEGIN:VEVENT END:VEVENT END:VCALENDAR
       BEGIN:VALARM ACTION:DISPLAY TRIGGER:-PT15M END:VALARM].each do |line|
      assert_equal 1, lines.count(line), line
    end
    assert_equal 1, lines.count { |line| line.start_with?("BEGIN:VEVENT") }
    assert_match(/\ADTSTAMP:\d{8}T\d{6}Z\z/, lines.find { |line| line.start_with?("DTSTAMP:") })
    assert_equal "3", property(body, "SEQUENCE")
    assert_equal "20300115T100000Z", property(body, "DTSTART")
    assert_equal "20300115T110000Z", property(body, "DTEND")
    assert_equal "Finalized event", property(body, "SUMMARY")
    assert_equal "Ege's place", property(body, "LOCATION")
    assert_equal "CONFIRMED", property(body, "STATUS")
    description = property(body, "DESCRIPTION")
    assert_includes description, "1. Pizza (30 min)\\n2. The movie"
    assert description.end_with?("Planned with Catching App"), description
    assert_not_includes description, "Margherita", "plan descriptions never reach the file"
    alarm = unfold(body)[/BEGIN:VALARM.*END:VALARM/m]
    assert_includes alarm, "DESCRIPTION:Finalized event"
  end

  test "the window is written in UTC and the file names no zone" do
    @event.update_columns(time_zone: "Europe/Berlin")

    body = render

    assert_includes body, "DTSTART:20300115T100000Z\r\n"
    assert_includes body, "DTEND:20300115T110000Z\r\n"
    assert_not_includes body, "VTIMEZONE"
    assert_not_includes body, "TZID"
    assert_not_includes body, "Europe/Berlin"
  end

  test "no place means no LOCATION, no link means no URL, and ORGANIZER never appears" do
    @event.update_columns(place: nil, place_url: nil)

    %i[page mail].each do |mode|
      body = render(mode: mode)
      assert_nil property(body, "LOCATION"), mode
      assert_nil property(body, "URL"), mode
      assert_not_includes body, "ORGANIZER", mode
      assert_not_includes body, "owner@example.com", mode
    end
  end

  test "the UID is stable through edits and cancellation and SEQUENCE follows the revision" do
    expected = "#{Digest::SHA256.hexdigest("#{@event.id}:#{@event.created_at.to_i}")[0, 32]}@example.com"
    first = render
    assert_equal expected, property(first, "UID")
    assert_equal "3", property(first, "SEQUENCE")

    @event.update_details!(name: "Renamed")
    second = render
    assert_equal expected, property(second, "UID")
    assert_equal "4", property(second, "SEQUENCE")
    assert_equal "Renamed", property(second, "SUMMARY")

    @event.cancel!
    third = render
    assert_equal expected, property(third, "UID")
    assert_equal "5", property(third, "SEQUENCE")
    assert_equal "CANCELLED", property(third, "STATUS")

    other = events(:planning)
    other.update_columns(status: true, start_time: Time.utc(2030, 1, 15, 10), end_time: Time.utc(2030, 1, 15, 11))
    assert_not_equal expected, property(CalendarFile.new(other, mode: :page).body, "UID")
  end

  test "a withdrawn window is cancelled at the caller's request while the event is not" do
    body = render(mode: :mail, window: [ Time.utc(2030, 1, 15, 9), Time.utc(2030, 1, 15, 10) ], status: :cancelled)

    assert_equal "CANCELLED", property(body, "STATUS")
    assert_equal "20300115T090000Z", property(body, "DTSTART")
    assert_equal "20300115T100000Z", property(body, "DTEND")
    assert_not @event.reload.cancelled?
    assert_equal "CONFIRMED", property(render(status: :confirmed), "STATUS")
  end

  test "reserved characters are escaped in text values" do
    @event.update_columns(name: "Pizza, then; the \\ movie", description: "First line\r\nSecond, line; with \\ slash")

    body = render

    assert_includes body, "SUMMARY:Pizza\\, then\\; the \\\\ movie\r\n"
    assert_includes body, "DESCRIPTION:First line\\nSecond\\, line\\; with \\\\ slash\\n\\n1. Pizza"
    assert_includes body, "\r\nDESCRIPTION:Pizza\\, then\\; the \\\\ movie\r\n", "the alarm names the event too"
  end

  test "a long description folds at 75 octets with continuation spaces and unfolds to the original" do
    description = (1..60).map { |n| "word#{n}" }.join(" ")
    assert_operator description.length, :>=, 300
    @event.update_columns(description: description)

    body = render
    physical = body.split("\r\n")

    assert physical.all? { |line| line.bytesize <= 75 }, physical.max_by(&:bytesize)
    continuations = physical.select { |line| line.start_with?(" ") }
    assert_operator continuations.size, :>=, 4
    assert continuations.all? { |line| line.bytesize > 1 }, "no empty continuation"
    assert_equal "#{description}\\n\\n1. Pizza (30 min)\\n2. The movie\\n\\nPlanned with Catching App", property(body, "DESCRIPTION")
  end

  test "an emoji name folds on a character boundary" do
    name = "🍕" * 30
    @event.update_columns(name: name)

    body = render
    physical = body.split("\r\n")

    assert physical.all? { |line| line.bytesize <= 75 }
    assert physical.all?(&:valid_encoding?), "a fold split a UTF-8 sequence"
    assert physical.any? { |line| line.start_with?("SUMMARY:") && line.bytesize > 70 }
    assert_equal name, property(body, "SUMMARY")
    assert_equal 30, property(body, "SUMMARY").scan("🍕").size
  end

  test "mail mode carries no link, no description and organizer text through mail_safe" do
    @event.update_columns(name: "Pizza night http://evil.example", place: "Zoom https://zoom.us/j/1",
      place_url: "https://zoom.us/j/9?pwd=secret", description: "Bring https://evil.example")
    @event.activities.first.update_columns(name: "Trailers https://evil.example/t")

    body = render(mode: :mail)

    assert_not_includes body, "://"
    assert_not_includes body, "pwd=secret", "place_url never reaches the attachment"
    assert_nil property(body, "URL")
    assert_equal "Pizza night evil.example", property(body, "SUMMARY")
    assert_equal "Zoom zoom.us/j/1", property(body, "LOCATION"), "the place keeps its words, minus the scheme"
    description = property(body, "DESCRIPTION")
    assert_equal "1. Trailers evil.example/t (30 min)\\n2. The movie\\n\\nPlanned with Catching App", description
    assert_not_includes body, "Bring"
  end

  test "page mode carries the join link and the description first" do
    @event.update_columns(name: "Pizza night http://evil.example", place_url: "https://zoom.us/j/1", description: "Bring https://evil.example")

    body = render(mode: :page)

    assert_equal "https://zoom.us/j/1", property(body, "URL")
    assert_equal "Pizza night http://evil.example", property(body, "SUMMARY")
    assert_equal "Bring https://evil.example\\n\\n1. Pizza (30 min)\\n2. The movie\\n\\nPlanned with Catching App", property(body, "DESCRIPTION")
  end

  test "the mail-mode file stays under 8 KB at every maximum" do
    @event.activities.delete_all
    20.times { |i| @event.activities.create!(name: "#{i}".ljust(80, "x"), duration: 240, position: i) }
    @event.update_columns(name: "n" * 120, place: "p" * 200, description: "d" * 2000)
    @event.reload

    body = render(mode: :mail)

    assert_operator body.bytesize, :<=, 8192
    assert_equal 20, property(body, "DESCRIPTION").scan("(4 h)").size
  end

  test "neither mode carries a capability token" do
    token = participants(:finalized_guest).issue_live_token!

    %i[page mail].each do |mode|
      body = render(mode: mode)
      assert_not_includes body, token, mode
      assert_not_includes body, "/p/", mode
    end
  end

  test "a pending event without a window and a bad mode are refused" do
    pending = events(:planning)

    error = assert_raises(ArgumentError) { CalendarFile.new(pending, mode: :page) }
    assert_equal "a set time is needed for a calendar file", error.message
    assert_raises(ArgumentError) { CalendarFile.new(@event, mode: :text) }
    assert_raises(ArgumentError) { CalendarFile.new(@event, mode: :mail, status: :tentative) }
    assert_includes CalendarFile.new(pending, mode: :mail, window: [ Time.utc(2030, 1, 15, 9), Time.utc(2030, 1, 15, 10) ]).body,
      "DTSTART:20300115T090000Z"
  end

  test "a lone carriage return or a control character cannot inject a property" do
    @event.update_columns(place: "Ege's place", description: "Line\u0007one\rATTENDEE:mailto:victim@example.com")
    body = CalendarFile.new(@event, mode: :page).body

    assert_equal body.scan(/\r/).size, body.scan(/\r\n/).size, "every CR belongs to a CRLF line end"
    assert_no_match(/^ATTENDEE:/, body.lines.map(&:chomp).join("\n"))
    assert_includes body, "DESCRIPTION:Lineone", "control characters are stripped"
  end

  test "the sequence can be pinned by the caller so a delayed job cannot publish a newer one" do
    @event.update_columns(revision: 7)

    assert_includes CalendarFile.new(@event, mode: :page).body, "SEQUENCE:7"
    assert_includes CalendarFile.new(@event, mode: :mail, window: [ @event.start_time, @event.end_time ], sequence: 3).body,
      "SEQUENCE:3"
  end
end
