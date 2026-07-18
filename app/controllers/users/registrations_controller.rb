module Users
  class RegistrationsController < Devise::RegistrationsController
    rate_limit to: 10, within: 3.minutes, only: :create
  end
end
