require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Jobs wait in the primary database, so queued mail outlives a restart.
  config.active_job.queue_adapter = :solid_queue
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  config.action_mailer.perform_caching = false
  mailer_from = ENV.fetch("MAILER_FROM")
  config.action_mailer.default_options = { from: mailer_from }
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST"),
    protocol: "https"
  }
  # OneSignal's email API; SMTP_ADDRESS switches back to plain SMTP.
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587),
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: :plain,
      enable_starttls_auto: true
    }
  else
    config.action_mailer.delivery_method = :onesignal
    config.action_mailer.onesignal_settings = {
      app_id: ENV.fetch("ONESIGNAL_APP_ID"),
      api_key: ENV.fetch("ONESIGNAL_API_KEY")
    }
  end

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.hosts = [ ENV.fetch("APP_HOST"), "www.#{ENV.fetch("APP_HOST")}" ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
