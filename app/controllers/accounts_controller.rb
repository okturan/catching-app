class AccountsController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    if @user.update(account_params)
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

  # Always challenged: a request without the current password is refused.
  def account_params
    params.expect(user: %i[first_name last_name email password password_confirmation])
      .merge(password_challenge: params.dig(:user, :password_challenge).to_s)
  end
end
