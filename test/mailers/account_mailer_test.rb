require "test_helper"

class AccountMailerTest < ActionMailer::TestCase
  setup { @user = users(:owner) }

  test "welcome greets by first name and carries a confirmation link that works" do
    mail = AccountMailer.welcome(@user)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "Catching App: welcome, Olivia", mail.subject
    token = mail.text_part.body.to_s[%r{/email_confirmations/(\S+)}, 1]
    assert_equal @user, User.find_by_token_for(:email_confirmation, token)
    assert_includes html_text(mail), "Confirm my email"
  end

  test "a confirmation link dies when the address changes" do
    token = AccountMailer.confirm_email(@user).text_part.body.to_s[%r{/email_confirmations/(\S+)}, 1]
    @user.update!(email: "olivia@example.com")
    assert_nil User.find_by_token_for(:email_confirmation, token)
  end

  test "a login link works once" do
    token = AccountMailer.login_link(@user).text_part.body.to_s[%r{/login_links/(\S+)}, 1]
    assert_equal @user, User.find_by_token_for(:login, token)

    @user.update!(login_link_used_at: Time.current)
    assert_nil User.find_by_token_for(:login, token)
  end

  test "email_changed goes to the old address and names both" do
    mail = AccountMailer.email_changed(@user, "old@example.com")

    assert_equal [ "old@example.com" ], mail.to
    [ html_text(mail), mail.text_part.body.to_s ].each do |body|
      assert_includes body, "no longer uses old@example.com"
      assert_includes body, "It now uses owner@example.com"
    end
  end

  test "password_changed says when and offers a reset" do
    mail = AccountMailer.password_changed(@user)
    assert_equal "Catching App: your password was changed", mail.subject
    assert_includes mail.text_part.body.to_s, "/passwords/new"
  end
end
