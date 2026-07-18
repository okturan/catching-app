module Users
  class PasswordsController < Devise::PasswordsController
    rate_limit to: 10, within: 3.minutes, only: :create
  end
end
