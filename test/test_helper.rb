ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("test_helpers/*.rb", __dir__)].each { require it }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include ActiveJob::TestHelper

    # The whole suite runs at one instant, after the fixtures' replies and
    # before their slots, so no test ages into failure.
    setup { travel_to Time.utc(2030, 1, 10, 12) }

  # Fixture digests are built from these literal raw tokens (see
  # test/fixtures/participants.yml), so tests can build real links.
  # What a reader sees in a mail's HTML part: the text, entities decoded.
  def html_text(mail)
    CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(mail.html_part.body.to_s)).gsub(/[ \t]+/, " ")
  end

  # The calendar file a mail links to, as CalendarLinksController serves it.
  def calendar_of(mail)
    token = mail.text_part.body.to_s[%r{/calendar/([^\s"<]+)}, 1] or flunk("no calendar link in the mail")
    CalendarLink.file_for(token).body
  end

  # A mail body without its calendar link, which is ours and opens no page.
  def outside_calendar(body)
    body.gsub(%r{https?://[^/\s]+/calendar/[^\s"<]+}, "")
  end

  def raw_token(fixture_name)
      fixture_name.to_s.delete("_").ljust(32, "0")
    end

    # rate_limit captured Rails.cache at class-body time; make its counter
    # report `count` for the duration of the block.
    def with_rate_limit_count(count)
      store = Rails.cache
      store.define_singleton_method(:increment) { |*, **| count }
      yield
    ensure
      store.singleton_class.remove_method(:increment)
    end
  end
end

class ActionDispatch::IntegrationTest
  include SessionTestHelper
end
