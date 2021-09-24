class Event < ApplicationRecord
  belongs_to :user
  has_many :time_slots
  has_many :users, through: :invitations
end
