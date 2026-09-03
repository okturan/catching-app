require "test_helper"

class ParticipantMailerTest < ActionMailer::TestCase
  setup do
    @mailer_from = ENV.delete("MAILER_FROM")
    @event = events(:planning)
    @organizer = participants(:planning_organizer)
    @guest = participants(:planning_guest)
    @token = "t" * 32
  end

  teardown do
    ENV["MAILER_FROM"] = @mailer_from if @mailer_from
  end

  def delivery(kind, participant)
    MailDelivery.create!(event: @event, participant: participant, kind: kind, recipient_email: participant.email,
      sender_email: kind == :invitation ? "owner@example.com" : nil)
  end

  test "organizer link is constant content with the link in both parts" do
    @event.update!(name: "Buy crypto now http://evil.example", description: "http://evil.example/desc")
    row = delivery(:organizer_link, @organizer)

    mail = ParticipantMailer.with(delivery: row, token: @token).organizer_link

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal [ "no-reply@catching.app" ], mail.from
    assert_equal "Catching App: your organizer link", mail.subject
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "/p/#{@token}"
      assert_not_includes body, "crypto"
      assert_not_includes body, "evil.example"
    end
  end

  test "invitation names the organizer first, carries the link and no organizer URL" do
    @event.update!(name: "Party https://evil.example/party", description: "Visit https://evil.example")
    @organizer.update!(name: "PayPal Support https://paypal.example")
    row = delivery(:invitation, @guest)

    mail = ParticipantMailer.with(delivery: row, token: @token).invitation

    assert_equal [ "invitee@example.com" ], mail.to
    assert_equal [ "owner@example.com" ], mail.reply_to
    assert mail.subject.start_with?("Catching App: PayPal Support"), mail.subject
    assert_operator mail.subject.length, :<=, 80
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "Invitation from PayPal Support paypal.example (owner@example.com)"
      assert_includes body, "/p/#{@token}"
      assert_not_includes body, "evil.example/desc", "the description never reaches the mail"
      assert_equal body.scan("http://example.com/p/").size, body.scan("://").size, "only the participation link may carry a scheme"
      assert_includes body, "You will get at most: up to 5 resends, one confirmation when you reply, and one message when the time is set."
      assert_includes body, "60-minute slots between 15 Jan and 15 Jan 2030 (UTC)"
    end
  end

  test "response confirmation coalesces ranges in both zones and carries no link" do
    @guest.update!(time_zone: "Asia/Kolkata")
    @event.replace_time_slots!(participant: @organizer, starts_at: [ 9, 10, 11, 14 ].map { |h| Time.utc(2030, 1, 15, h) })
    @event.replace_time_slots!(participant: @guest, starts_at: [ 9, 10, 11, 14 ].map { |h| Time.utc(2030, 1, 15, h) })
    row = delivery(:response_confirmation, @guest)

    mail = ParticipantMailer.with(delivery: row, token: nil).response_confirmation

    assert_equal "Catching App: your reply to Planning session is saved", mail.subject
    text = mail.text_part.body.to_s
    assert_includes text, "Tue 15 Jan 2030: 14:30–17:30, 19:30–20:30"
    assert_includes text, "(Asia/Kolkata)"
    assert_includes text, "Tue 15 Jan 2030: 09:00–12:00, 14:00–15:00"
    assert_not_includes text, "/p/"
  end

  test "finalized renders the window in the recipient zone and the event zone" do
    finalized = events(:finalized)
    guest = participants(:finalized_guest)
    guest.update!(time_zone: "Europe/Berlin")
    row = MailDelivery.create!(event: finalized, participant: guest, kind: :finalized, recipient_email: guest.email)

    mail = ParticipantMailer.with(delivery: row, token: nil).finalized

    assert_equal "Catching App: Finalized event is set for Tue 15 Jan", mail.subject
    assert_equal [ "owner@example.com" ], mail.reply_to
    text = mail.text_part.body.to_s
    assert_includes text, "Tue 15 Jan 2030 11:00–12:00 (Europe/Berlin)"
    assert_includes text, "Tue 15 Jan 2030 10:00–11:00 (UTC)"
  end

  test "header injection through the event name is neutralized" do
    @event.update!(name: "Dinner\r\nBcc: victim@example.com")
    row = delivery(:invitation, @guest)

    mail = ParticipantMailer.with(delivery: row, token: @token).invitation

    assert_no_match(/[\r\n]/, mail.subject)
    assert_nil mail.bcc
  end

  test "delivery marks the ledger row" do
    row = delivery(:organizer_link, @organizer)

    ParticipantMailer.with(delivery: row, token: @token).organizer_link.deliver_now

    assert row.reload.delivered_at.present?
  end

  test "every preview renders" do
    ActionMailer::Preview.all.each do |preview|
      preview.emails.each do |email|
        assert_nothing_raised { preview.call(email) }
      end
    end
    assert_includes ActionMailer::Preview.all.map(&:name), "ParticipantMailerPreview"
  end
end
