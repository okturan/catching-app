ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  fixtures :all

  # Fixture digests are built from these literal raw tokens (see
  # test/fixtures/participants.yml), so tests can build real links.
  def raw_token(fixture_name)
    fixture_name.to_s.delete("_").ljust(32, "0")
  end

  # rate_limit captured Rails.cache at class-body time; make its counter
  # report `count` for the duration of the block.
  def with_rate_limit_count(count)
    store = Rails.cache
    store.define_singleton_method(:increment) { |*_args, **_options| count }
    yield
  ensure
    store.singleton_class.remove_method(:increment)
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
