class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  has_many :events, dependent: :destroy, inverse_of: :user
  has_many :time_slots, dependent: :destroy, inverse_of: :user
  has_many :user_events, dependent: :destroy, inverse_of: :user
  has_many :invited_events, through: :user_events, source: :event

  validates :first_name, :last_name, presence: true

  def full_name
    "#{first_name} #{last_name}".squish
  end
end
