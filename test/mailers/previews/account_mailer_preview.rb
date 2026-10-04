# Preview at /rails/mailers/account_mailer.
class AccountMailerPreview < ActionMailer::Preview
  def welcome = AccountMailer.welcome(user)
  def confirm_email = AccountMailer.confirm_email(user)
  def login_link = AccountMailer.login_link(user)
  def password_changed = AccountMailer.password_changed(user)
  def email_changed = AccountMailer.email_changed(user, "old.address@example.com")

  private

  def user = User.first || User.new(id: 0, first_name: "Maya", last_name: "Chen", email: "maya@example.com")
end
