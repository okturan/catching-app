require "test_helper"

class InviteeListParserTest < ActiveSupport::TestCase
  test "splits on commas and newlines, normalizes, dedupes and drops the organizer" do
    parsed = InviteeListParser.call(
      "Bob@Example.com, cy@example.com\nbob@example.com\n\nann@example.com",
      organizer_email: "Ann@example.com"
    )

    assert_equal %w[bob@example.com cy@example.com], parsed
  end

  test "names an invalid address" do
    error = assert_raises(ArgumentError) { InviteeListParser.call("bob@example.com, not-an-address", organizer_email: "a@b.example") }

    assert_equal "not-an-address is not a valid email address", error.message
  end

  test "caps the list at fifty and the body at four kilobytes" do
    fifty_one = 51.times.map { |i| "guest#{i}@example.com" }.join("\n")
    error = assert_raises(ArgumentError) { InviteeListParser.call(fifty_one, organizer_email: "a@b.example") }
    assert_equal "Invite at most 50 people", error.message

    assert_raises(ArgumentError) { InviteeListParser.call("x" * 4097, organizer_email: "a@b.example") }
    assert_equal [], InviteeListParser.call("", organizer_email: "a@b.example")
  end
end
