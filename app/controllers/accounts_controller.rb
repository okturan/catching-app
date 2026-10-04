class AccountsController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    previous_email = @user.email
    if @user.update(account_params)
      tell_about_changes(previous_email)
      redirect_to edit_account_path, notice: "Your account was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    Current.user.destroy!
    cookies.delete(:session_id)
    redirect_to root_path, notice: "Your account was deleted.", status: :see_other
  end

  private

  # A new address is unconfirmed until its link is used, and the old one
  # hears about the change; a new password is reported to the account.
  def tell_about_changes(previous_email)
    new_email = @user.saved_change_to_email?
    new_password = @user.saved_change_to_password_digest?
    if new_email
      @user.update_column(:email_confirmed_at, nil)
      AccountMailer.confirm_email(@user).deliver_later
      AccountMailer.email_changed(@user, previous_email).deliver_later
    end
    AccountMailer.password_changed(@user).deliver_later if new_password
  end

  # Always challenged: a request without the current password is refused.
  def account_params
    params.expect(user: %i[first_name last_name email password password_confirmation])
      .merge(password_challenge: params.dig(:user, :password_challenge).to_s)
  end
end
