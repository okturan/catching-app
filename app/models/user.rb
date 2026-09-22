# An account. It remembers the events its owner planned or claimed while
# signed in; every event is still reached through its capability link.
#
# Validations are declared in the sign-up form's order, so its error
# summary reads top to bottom.
class User < ApplicationRecord
  PASSWORD_MINIMUM = 15

  has_many :sessions, dependent: :delete_all
  has_many :participants

  normalizes :email, with: -> { it.strip.downcase }

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { minimum: PASSWORD_MINIMUM }, allow_nil: true
  # A reset must set a password; everywhere else a blank one keeps the old.
  validates :password, presence: true, on: :password_reset
  has_secure_password reset_token: { expires_in: 1.hour }

  def full_name
    "#{first_name} #{last_name}".squish
  end
end
