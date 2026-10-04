# The mails an account is sent: welcome, address confirmation, login links,
# and a notice for every change to how the account is reached.
class AccountMailer < ApplicationMailer
  SUBJECT_PREFIX = "Catching App: ".freeze

  def welcome(user)
    @user = user
    @confirm_url = email_confirmation_url(user.generate_token_for(:email_confirmation))
    mail to: user.email, subject: "#{SUBJECT_PREFIX}welcome, #{user.first_name}"
  end

  def confirm_email(user)
    @user = user
    @confirm_url = email_confirmation_url(user.generate_token_for(:email_confirmation))
    mail to: user.email, subject: "#{SUBJECT_PREFIX}confirm your email address"
  end

  def login_link(user)
    @user = user
    @login_url = login_link_url(user.generate_token_for(:login))
    mail to: user.email, subject: "#{SUBJECT_PREFIX}your login link"
  end

  def password_changed(user)
    @user = user
    mail to: user.email, subject: "#{SUBJECT_PREFIX}your password was changed"
  end

  # Sent to the address the account used to have.
  def email_changed(user, previous_email)
    @user = user
    @previous_email = previous_email
    mail to: previous_email, subject: "#{SUBJECT_PREFIX}your account's email address was changed"
  end
end
