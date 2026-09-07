# Capability tokens travel in the request path, so the request log line would
# otherwise print every live credential. Mask them before the line is written.
class TokenMaskingRackLogger < Rails::Rack::Logger
  TOKEN_PATH = %r{/p/[A-Za-z0-9]{32}}

  private

  def started_request_message(request)
    super.gsub(TOKEN_PATH, "/p/[FILTERED]")
  end
end

Rails.application.config.middleware.swap(Rails::Rack::Logger, TokenMaskingRackLogger, Rails.application.config.log_tags)
