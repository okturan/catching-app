class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many attempts. Try again in a few minutes.", status: :see_other }

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[first_name last_name email password password_confirmation]))

    if @user.save
      AccountMailer.welcome(@user).deliver_later
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome! Confirm your address from the email we just sent.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end
end
