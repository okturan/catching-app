class Event < ApplicationRecord
  belongs_to :user
  FRIENDS = User.all
end
