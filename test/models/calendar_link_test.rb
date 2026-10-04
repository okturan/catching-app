require "test_helper"

class CalendarLinkTest < ActiveSupport::TestCase
  setup do
    @event = events(:finalized)
    @window = [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ]
  end

  test "a token gives back the file it was signed for" do
    token = CalendarLink.token_for(@event, window: @window, status: :cancelled, sequence: 7)

    file = CalendarLink.file_for(token).body
    assert_includes file, "STATUS:CANCELLED"
    assert_includes file, "DTSTART:20300115T100000Z"
    assert_includes file, "DTEND:20300115T110000Z"
    assert_includes file, "SEQUENCE:7"
    assert_match(/\A[0-9a-z.]+\.[A-Za-z0-9_-]+\z/, token)
  end

  test "a changed, expired or truncated token gives nothing" do
    token = CalendarLink.token_for(@event, window: @window, status: :confirmed, sequence: 1)
    assert_nil CalendarLink.file_for(token.sub(".c.", ".x."))
    assert_nil CalendarLink.file_for(token.chop)
    assert_nil CalendarLink.file_for(token, now: 13.months.from_now)
    assert_nil CalendarLink.file_for("")
    assert_nil CalendarLink.file_for(nil)
  end

  test "the link serves the file without any session or participant link" do
    token = CalendarLink.token_for(@event, window: @window, status: :confirmed, sequence: 2)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get "/calendar/#{token}"
    assert_equal 200, session.response.status
    assert_equal "text/calendar", session.response.media_type
    assert_includes session.response.body, "STATUS:CONFIRMED"

    session.get "/calendar/#{token.chop}"
    assert_equal 404, session.response.status
  end
end
