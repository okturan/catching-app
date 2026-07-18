require "test_helper"

class UserEventTest < ActiveSupport::TestCase
  test "prevents duplicate invitations" do
    invitation = UserEvent.new(user: users(:invitee), event: events(:planning))

    assert_not invitation.valid?
    assert_includes invitation.errors[:user_id], "has already been taken"
  end

  test "does not allow the organizer to be invited" do
    invitation = UserEvent.new(user: users(:owner), event: events(:planning))

    assert_not invitation.valid?
    assert_includes invitation.errors[:user], "cannot invite the event organizer"
  end
end
