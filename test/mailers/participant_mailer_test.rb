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

  def finalized_mail(participant, token: nil, event: events(:finalized), window: nil)
    row = MailDelivery.create!(event: event, participant: participant, kind: :finalized, recipient_email: participant.email)
    window ||= [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ]
    ParticipantMailer.with(delivery: row, token: token, window: window).finalized
  end

  test "finalized renders the window, the facts and the plan in the recipient zone and the event zone" do
    finalized = events(:finalized)
    finalized.update_columns(slot_minutes: 30)
    finalized.update!(place: "Ege's place", place_url: "https://maps.example/x", duration_minutes: 90)
    finalized.activities.create!(name: "Pizza https://evil.example", duration: 30, position: 0, description: "Margherita https://evil.example/m")
    finalized.activities.create!(name: "The movie", position: 1)
    guest = participants(:finalized_guest)
    guest.update!(time_zone: "Europe/Berlin")

    mail = finalized_mail(guest)

    assert_equal "Catching App: Finalized event is set for Tue 15 Jan", mail.subject
    assert_equal [ "owner@example.com" ], mail.reply_to
    [ CGI.unescapeHTML(mail.html_part.body.to_s), mail.text_part.body.to_s ].each do |body|
      assert_includes body, "Tue 15 Jan 2030 11:00–12:00 (Europe/Berlin)"
      assert_includes body, "Tue 15 Jan 2030 10:00–11:00 (UTC)"
      assert_includes body, "Where: Ege's place"
      assert_includes body, "How long: 1 h 30 min"
      assert_includes body, "Pizza evil.example (30 min) at 11:00 (Europe/Berlin), 10:00 (UTC)"
      assert_includes body, "The movie at 11:30 (Europe/Berlin), 10:30 (UTC)"
      assert_not_includes body, "Margherita"
      assert_not_includes body, "maps.example", "place_url never reaches a mail"
      assert_includes body, "You will hear from us again only if the organizer changes the plan, reopens the time or cancels."
      assert_not_includes body, "This is the last message about this event."
      assert_equal body.scan("://").size, body.scan("http://example.com/participations/#{guest.id}").size, "only the participation link carries a scheme"
    end
    assert_not_includes mail.subject, "maps.example"
    assert_not_includes mail.attachments.first.body.decoded, "maps.example"
  end

  test "finalized links a claimed guest to the signed-in page and ends with the Leave sentence" do
    guest = participants(:finalized_guest)
    assert guest.claimed?

    mail = finalized_mail(guest)

    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "http://example.com/participations/#{guest.id}"
      assert_not_includes body, "/p/"
    end
    text = mail.text_part.body.to_s.strip
    assert text.end_with?("You will hear from us again only if the organizer changes the plan, reopens the time or cancels.\n\nTo stop hearing about this event, open your link and choose Leave this event."), text
  end

  test "finalized links an unclaimed guest through the pending token it was handed" do
    guest = participants(:finalized_guest)
    guest.update!(user: nil)
    pending = guest.issue_pending_token!

    mail = finalized_mail(guest, token: pending)

    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "http://example.com/p/#{pending}"
      assert_not_includes body, "/participations/"
      assert_equal body.scan("http://example.com/p/#{pending}").size, body.scan("://").size, "only the participation link carries a scheme"
      assert_includes body, "To stop hearing about this event, open your link and choose Leave this event."
    end
  end

  test "the organizer's finalized copy carries no link and no Leave sentence" do
    organizer = participants(:finalized_organizer)

    mail = finalized_mail(organizer)

    assert_equal [ "owner@example.com" ], mail.to
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "Open your organizer link"
      assert_not_includes body, "://"
      assert_not_includes body, "/p/"
      assert_not_includes body, "/participations/"
      assert_not_includes body, "Leave this event"
      assert_includes body, "You will hear from us again only if the organizer changes the plan, reopens the time or cancels."
    end
    assert_equal [ "catching-app.ics" ], mail.attachments.map(&:filename)
  end

  test "finalized attaches a confirmed calendar file built from the window params" do
    finalized = events(:finalized)
    finalized.update_columns(revision: 4, place_url: "https://zoom.us/j/1", place: "Zoom")
    finalized.update_columns(status: false, start_time: nil, end_time: nil)

    mail = finalized_mail(participants(:finalized_guest), event: finalized)

    assert_equal 1, mail.attachments.size
    attachment = mail.attachments["catching-app.ics"]
    assert_equal "text/calendar", attachment.mime_type
    assert_equal "PUBLISH", attachment.content_type_parameters["method"]
    file = attachment.body.decoded
    assert file.start_with?("BEGIN:VCALENDAR")
    assert_includes file, "DTSTART:20300115T100000Z"
    assert_includes file, "DTEND:20300115T110000Z"
    assert_includes file, "STATUS:CONFIRMED"
    assert_includes file, "SEQUENCE:4"
    assert_includes file, "LOCATION:Zoom"
    assert_not_includes file, "://"
    assert_not_includes file, "URL:"
    assert_operator file.bytesize, :<=, 8192
    assert_includes mail.text_part.body.to_s, "Tue 15 Jan 2030 10:00–11:00 (UTC)"
  end

  test "cancelled names the organizer, prints the window from its params in both zones and carries no link" do
    finalized = events(:finalized)
    guest = participants(:finalized_guest)
    guest.update!(time_zone: "Europe/Berlin")
    participants(:finalized_organizer).update!(name: "Olivia https://evil.example Owner")
    finalized.cancel!
    row = MailDelivery.create!(event: finalized, participant: guest, kind: :cancelled, recipient_email: guest.email, sender_email: "owner@example.com")

    mail = ParticipantMailer.with(delivery: row, token: nil, window: [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ]).cancelled

    assert_equal "Catching App: Finalized event is cancelled", mail.subject
    assert_equal [ "invitee@example.com" ], mail.to
    assert_equal [ "owner@example.com" ], mail.reply_to
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "Olivia evil.example Owner cancelled"
      assert_includes body, "Finalized event"
      assert_includes body, "It was set for Tue 15 Jan 2030 11:00–12:00 (Europe/Berlin)."
      assert_includes body, "In the event's zone: Tue 15 Jan 2030 10:00–11:00 (UTC)"
      assert_includes body, "Nothing else will be sent about this event."
      assert_not_includes body, "/p/"
      assert_not_includes body, "://"
    end
  end

  test "cancelled without a window says nothing about a set time" do
    @event.cancel!
    row = delivery(:cancelled, @organizer)

    mail = ParticipantMailer.with(delivery: row, token: nil, window: nil).cancelled

    assert_equal "Catching App: Planning session is cancelled", mail.subject
    assert_equal [ "owner@example.com" ], mail.to
    text = mail.text_part.body.to_s
    assert_includes text, "Olivia Owner cancelled Planning session."
    assert_includes text, "Nothing else will be sent about this event."
    assert_not_includes text, "It was set for"
    assert_not_includes text, "In the event's zone"
    assert_not_includes text, "://"
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
