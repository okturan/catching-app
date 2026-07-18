require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module CatchingApp
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks templates])

    config.generators do |generate|
      generate.assets false
      generate.helper false
      generate.system_tests nil
      generate.test_framework :test_unit, fixture: true
    end
  end
end
