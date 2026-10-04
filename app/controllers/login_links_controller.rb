# Logging in by an emailed link instead of a password. Asking never tells
# whether an address has an account; a link works once, for 15 minutes.
class LoginLinksController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_login_link_path, alert: "Too many attempts. Try again in a few minutes.", status: :see_other }

  def new
  end

  def create
    if (user = User.find_by(email: params[:email].to_s.strip.downcase))
      AccountMailer.login_link(user).deliver_later
    end
    redirect_to new_session_path, notice: "If that address has an account, a login link is on its way. It works for 15 minutes.", status: :see_other
  end

  # Using the link proves the address too.
  def show
    user = User.find_by_token_for(:login, params[:token])
    if user
      user.update!(login_link_used_at: Time.current, email_confirmed_at: user.email_confirmed_at || Time.current)
      start_new_session_for user
      redirect_to after_authentication_url, notice: "You're logged in.", status: :see_other
    else
      redirect_to new_login_link_path, alert: "That login link is invalid, used or expired. Ask for a new one.", status: :see_other
    end
  end
end
