# Confirming an account's address, from the emailed link; and sending the
# link again from the account page.
class EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access only: :show
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to edit_account_path, alert: "Try again in a few minutes.", status: :see_other }

  def show
    user = User.find_by_token_for(:email_confirmation, params[:token])
    if user
      user.confirm_email!
      redirect_to(authenticated? ? edit_account_path : new_session_path, notice: "Your email address is confirmed.", status: :see_other)
    else
      redirect_to root_path, alert: "That confirmation link is invalid or has expired.", status: :see_other
    end
  end

  def create
    AccountMailer.confirm_email(Current.user).deliver_later unless Current.user.email_confirmed?
    redirect_to edit_account_path, notice: "A confirmation link is on its way to #{Current.user.email}.", status: :see_other
  end
end
