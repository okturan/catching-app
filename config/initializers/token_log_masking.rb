# Capability tokens travel in the request path, so every log line that prints
# a path would print a live credential: the request line and the redirect
# line both mask it.
class TokenMaskingRackLogger < Rails::Rack::Logger
  TOKEN_PATH = %r{/p/[A-Za-z0-9]{32}}

  private

  def started_request_message(request)
    super.gsub(TOKEN_PATH, "/p/[FILTERED]")
  end
end

Rails.application.config.filter_redirect << TokenMaskingRackLogger::TOKEN_PATH
Rails.application.config.middleware.swap(Rails::Rack::Logger, TokenMaskingRackLogger, Rails.application.config.log_tags)
