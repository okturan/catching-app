require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires first and last names" do
    user = User.new(
      email: "nameless@example.com",
      password: "correct horse battery staple",
      password_confirmation: "correct horse battery staple"
    )

    assert_not user.valid?
    assert_includes user.errors[:first_name], "can't be blank"
    assert_includes user.errors[:last_name], "can't be blank"
  end

  test "returns a normalized full name" do
    user = users(:owner)
    user.first_name = "  Olivia "
    user.last_name = " Owner  "

    assert_equal "Olivia Owner", user.full_name
  end

  test "requires a valid email address" do
    user = User.new(
      first_name: "Valid",
      last_name: "Name",
      email: "not-an-email",
      password: "correct horse battery staple"
    )

    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "requires a password of at least fifteen characters" do
    user = User.new(
      first_name: "Valid",
      last_name: "Name",
      email: "password@example.com",
      password: "too-short"
    )

    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 15 characters)"
  end
end
