# A forgotten password: a link by mail, valid for an hour, to set a new one.
# Asking never tells whether an address has an account, and setting one
# signs out every browser.
class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Too many attempts. Try again in a few minutes.", status: :see_other }

  def new
  end

  def create
    if (user = User.find_by(email: params[:email]))
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "If that address has an account, a link to reset its password is on its way.", status: :see_other
  end

  def edit
  end

  def update
    @user.assign_attributes(params.expect(user: %i[password password_confirmation]))

    if @user.save(context: :password_reset)
      @user.sessions.delete_all
      redirect_to new_session_path, notice: "Your password was changed. Log in with the new one.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: "That reset link is invalid or has expired. Ask for a new one.", status: :see_other
  end
end
