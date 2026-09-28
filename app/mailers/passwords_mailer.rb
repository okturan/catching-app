class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail to: user.email, subject: "Catching App: reset your password"
  end
end
