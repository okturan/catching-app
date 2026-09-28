# One signed-in browser, found through a signed cookie.
class Session < ApplicationRecord
  belongs_to :user
end
