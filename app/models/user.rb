# An account remembers events; each is still reached through its link.
# Validations follow the sign-up form's order, so its summary reads down.
class User < ApplicationRecord
  PASSWORD_MINIMUM = 15

  has_many :sessions, dependent: :delete_all
  has_many :participants

  normalizes :email, with: -> { it.strip.downcase }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }, uniqueness: true
  validates :password, length: { minimum: PASSWORD_MINIMUM }, allow_nil: true
  # A reset must set a password; everywhere else a blank one keeps the old.
  validates :password, presence: true, on: :password_reset
  has_secure_password reset_token: { expires_in: 1.hour }

  # A confirmation link stops working once the address changes again.
  generates_token_for :email_confirmation, expires_in: 3.days do
    email
  end

  # A login link works once: using one moves this mark, which logging out
  # does not undo.
  generates_token_for :login, expires_in: 15.minutes do
    login_link_used_at&.to_f
  end

  def email_confirmed?
    email_confirmed_at?
  end

  def confirm_email!
    update!(email_confirmed_at: Time.current) unless email_confirmed?
  end

  def full_name
    "#{first_name} #{last_name}".squish
  end
end
