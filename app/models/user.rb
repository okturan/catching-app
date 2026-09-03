class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  has_many :participants, dependent: :nullify, inverse_of: :user
  has_many :events, through: :participants

  validates :first_name, :last_name, presence: true

  def full_name
    "#{first_name} #{last_name}".squish
  end
end
