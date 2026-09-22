class ApplicationController < ActionController::Base
  include Authentication

  # The grid's real floor: the newest API it uses is Intl.supportedValuesOf.
  allow_browser versions: { safari: 15.4, chrome: 99, firefox: 93, opera: 85, ie: false },
    block: -> { render "errors/unsupported_browser", status: :not_acceptable }

  default_form_builder ApplicationFormBuilder
end
