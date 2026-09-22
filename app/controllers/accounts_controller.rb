# The signed-in person's own account: name, address and password, each
# change proven with the current password, and the way out.
class AccountsController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    if @user.update(account_params)
      redirect_to edit_account_path, notice: "Your account was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # The events stay: their participations only forget the account.
  def destroy
    Current.user.destroy!
    cookies.delete(:session_id)
    redirect_to root_path, notice: "Your account was deleted.", status: :see_other
  end

  private

  # The challenge is always made: a request without the current password is
  # checked against an empty one and refused.
  def account_params
    params.expect(user: %i[first_name last_name email password password_confirmation])
      .merge(password_challenge: params.dig(:user, :password_challenge).to_s)
  end
end
