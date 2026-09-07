require "test_helper"

class TimeSlotParserTest < ActiveSupport::TestCase
  test "parses, normalizes, sorts, and deduplicates ISO timestamps" do
    parsed = TimeSlotParser.call(
      "2030-01-15T12:00:00+02:00,2030-01-15T09:00:00Z,2030-01-15T12:00:00+02:00"
    )

    assert_equal [ Time.utc(2030, 1, 15, 9), Time.utc(2030, 1, 15, 10) ], parsed
  end

  test "requires ISO 8601 timestamps" do
    error = assert_raises(ArgumentError) { TimeSlotParser.call("tomorrow morning") }

    assert_equal "Time slots must use ISO 8601 timestamps", error.message
  end

  test "requires at least one timestamp" do
    error = assert_raises(ArgumentError) { TimeSlotParser.call("") }

    assert_equal "Select at least one time slot", error.message
  end

  test "rejects timestamps spanning more than 31 days" do
    error = assert_raises(ArgumentError) do
      TimeSlotParser.call("2030-01-01T10:00:00Z,2030-02-02T10:00:00Z")
    end

    assert_equal "Time slots must fit within a 31-day window", error.message
  end

  test "rejects more than the maximum number of timestamps" do
    values = (TimeSlotParser::MAX_SLOTS + 1).times.map do |offset|
      (Time.utc(2030, 1, 1) + offset.hours).iso8601
    end

    error = assert_raises(ArgumentError) { TimeSlotParser.call(values.join(",")) }

    assert_equal "Select no more than #{TimeSlotParser::MAX_SLOTS} time slots", error.message
  end

  test "the cap scales with the slot length" do
    assert_equal 775, TimeSlotParser.max_slots(60)
    assert_equal 1550, TimeSlotParser.max_slots(30)
    assert_equal 3100, TimeSlotParser.max_slots(15)

    values = 3101.times.map { |offset| (Time.utc(2030, 1, 1) + (offset * 15).minutes).iso8601 }
    error = assert_raises(ArgumentError) { TimeSlotParser.call(values.join(","), slot_minutes: 15) }
    assert_equal "Select no more than 3100 time slots", error.message
  end

  test "rejects instants from before yesterday" do
    error = assert_raises(ArgumentError) { TimeSlotParser.call(2.days.ago.utc.iso8601) }

    assert_equal "Select time slots from today onward", error.message
  end
end
