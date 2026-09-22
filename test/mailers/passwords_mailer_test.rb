require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "the reset mail carries a link to choose a new password" do
    mail = PasswordsMailer.reset(users(:owner))

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "Catching App: reset your password", mail.subject
    assert_match %r{/passwords/[^/\s]+/edit}, mail.text_part.body.to_s
    assert_match "works for an hour", mail.html_part.body.to_s
  end
end
