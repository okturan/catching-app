class ApplicationController < ActionController::Base
  # The grid's real floor: the newest API it uses is Intl.supportedValuesOf.
  allow_browser versions: { safari: 15.4, chrome: 99, firefox: 93, opera: 85, ie: false },
    block: -> { render "errors/unsupported_browser", status: :not_acceptable }

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || dashboard_path
  end

  def configure_permitted_parameters
    attributes = %i[first_name last_name email password password_confirmation current_password]
    devise_parameter_sanitizer.permit(:sign_up, keys: attributes)
    devise_parameter_sanitizer.permit(:account_update, keys: attributes)
  end
end
