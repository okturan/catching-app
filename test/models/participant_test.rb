require "test_helper"

class ParticipantTest < ActiveSupport::TestCase
  test "a live token finds the participant and the digest is all that is stored" do
    guest = participants(:planning_unsent)

    raw = guest.issue_live_token!

    assert_match Participant::Tokens::FORMAT, raw
    assert_equal Digest::SHA256.hexdigest(raw), guest.reload.token_digest
    assert_equal guest, Participant.find_by_link_token(raw)
    assert_nil Participant.find_by_link_token(raw.reverse)
  end

  test "a malformed token runs zero queries" do
    assert_queries_count(0) { assert_nil Participant.find_by_link_token("short") }
  end

  test "trailing punctuation from a mail client is stripped, and paths carry the clean token" do
    guest = Participant.find_by_link_token("#{raw_token(:planning_guest)}.")

    assert_equal participants(:planning_guest), guest
    assert_equal raw_token(:planning_guest), guest.to_param
    assert_not guest.found_by_pending_token?
    assert_equal guest.id.to_s, participants(:planning_guest).to_param, "a participant not found by a link is named by id"
  end

  test "a pending token finds the participant and changes nothing until it is promoted" do
    guest = participants(:planning_guest)
    old_raw = raw_token(:planning_guest)

    pending_raw = guest.issue_pending_token!
    found = Participant.find_by_link_token(pending_raw)

    assert found.found_by_pending_token?
    assert_equal guest, found
    assert_equal guest, Participant.find_by_link_token(old_raw)
    assert_nil guest.reload.pending_token_expires_at
    assert_equal users(:invitee).id, guest.user_id

    assert found.promote_pending!(actor: nil)
    assert_equal Participant.digest(pending_raw), found.token_digest
    assert_nil found.pending_token_digest
    assert_nil found.user_id, "promotion by someone other than the claimant clears the claim"
    assert_nil Participant.find_by_link_token(old_raw)
  end

  test "promotion by the claiming account keeps the claim" do
    pending_raw = participants(:planning_guest).issue_pending_token!

    Participant.find_by_link_token(pending_raw).promote_pending!(actor: users(:invitee))

    assert_equal users(:invitee).id, participants(:planning_guest).reload.user_id
  end

  test "an expired organizer recovery token is refused" do
    organizer = participants(:planning_organizer)
    pending_raw = organizer.issue_pending_token!(expires_in: 24.hours)

    assert_equal organizer, Participant.find_by_link_token(pending_raw)
    travel 25.hours do
      assert_nil Participant.find_by_link_token(pending_raw)
    end
  end

  test "the database never lets a guest who left hold a credential" do
    left = participants(:planning_left)

    assert_raises(ActiveRecord::StatementInvalid) { Participant.transaction(requires_new: true) { left.issue_live_token! } }
    assert_raises(ActiveRecord::StatementInvalid) { Participant.transaction(requires_new: true) { left.issue_pending_token! } }
  end

  test "emails are normalized and strictly formatted" do
    participant = events(:planning).participants.build(role: :guest, email: "  New.Guest@Example.COM ")

    assert participant.valid?
    assert_equal "new.guest@example.com", participant.email

    [ "a@b.example,c@d.example", "Bob <bob@example.com>", "no-at-sign", "x" * 250 + "@e.co" ].each do |bad|
      participant.email = bad
      assert_not participant.valid?, "#{bad.inspect} should be invalid"
    end
  end

  test "the database rejects an unnormalized email" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Participant.transaction(requires_new: true) do
        Participant.connection.execute("UPDATE participants SET email = 'Pending@example.com' WHERE id = #{participants(:planning_pending).id}")
      end
    end
  end

  test "names are squished, bounded and required for organizers" do
    guest = participants(:planning_pending)
    guest.name = "Ann\r\nBcc: victim@example.com"
    assert guest.valid?
    assert_no_match(/[\r\n]/, guest.name)

    guest.name = "x" * 101
    assert_not guest.valid?

    organizer = participants(:planning_organizer)
    organizer.name = " "
    assert_not organizer.valid?
    assert_includes organizer.errors[:name], "can't be blank"
  end

  test "display name never leaks an email to other guests" do
    guest = participants(:planning_pending)

    assert_equal "Guest", guest.display_name
    assert_equal "Ian Invitee", participants(:planning_guest).display_name
  end

  test "one email per event and one organizer per event" do
    duplicate = events(:planning).participants.build(role: :guest, email: "invitee@example.com")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"

    assert_raises(ActiveRecord::RecordNotUnique) do
      Participant.transaction(requires_new: true) do
        events(:planning).participants.create!(role: :organizer, email: "second@example.com", name: "Second")
      end
    end
  end

  test "state checks are enforced by the database" do
    guest = participants(:planning_pending)

    assert_raises(ActiveRecord::StatementInvalid) do
      Participant.transaction(requires_new: true) { guest.update_columns(declined_at: Time.current) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Participant.transaction(requires_new: true) { guest.update_columns(left_at: Time.current) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Participant.transaction(requires_new: true) { guest.update_columns(token_digest: "short") }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Participant.transaction(requires_new: true) { guest.update_columns(pending_token_expires_at: Time.current) }
    end
  end

  test "scopes define who counts" do
    event = events(:planning)

    assert_equal [ participants(:planning_organizer), participants(:planning_guest) ].sort_by(&:id),
      event.participants.counting.order(:id).to_a
    assert_equal [ participants(:planning_unsent) ], event.participants.unsent.to_a
    assert_not_includes event.participants.active, participants(:planning_left)
    assert_includes event.participants.linked, participants(:planning_pending)

    voided = participants(:planning_pending)
    voided.update_columns(responded_at: 2.days.ago, reply_voided_at: 1.day.ago)
    assert_not_includes event.participants.counting, voided, "a voided reply does not count"
    assert_not voided.reload.counting?
    assert voided.voided?
    assert participants(:planning_guest).counting?, "a guest who still holds a pick counts"
    assert_includes event.participants.active.linked, voided, "voided guests keep their link and stay active"
  end

  test "only an open guest reply can be voided" do
    declined = participants(:planning_pending)
    declined.update_columns(responded_at: Time.current, declined_at: Time.current)

    [ declined, participants(:planning_unsent), participants(:planning_organizer), participants(:planning_left) ].each do |row|
      assert_raises(ActiveRecord::StatementInvalid, row.email) do
        Participant.transaction(requires_new: true) { row.update_columns(reply_voided_at: Time.current) }
      end
      assert_nil row.reload.reply_voided_at
    end

    voided = participants(:planning_guest)
    voided.update_columns(reply_voided_at: Time.current)
    assert_raises(ActiveRecord::StatementInvalid, "declining without clearing the void is refused per statement") do
      Participant.transaction(requires_new: true) { voided.update_columns(declined_at: Time.current) }
    end
  end

  test "one account is one participant per event" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Participant.transaction(requires_new: true) do
        participants(:planning_pending).update_columns(user_id: users(:owner).id)
      end
    end
  end

  test "deleting an account lets go of its participants and keeps the event" do
    slots_before = TimeSlot.count

    users(:owner).destroy!

    assert_nil participants(:planning_organizer).reload.user_id
    assert Event.exists?(events(:planning).id)
    assert_equal slots_before, TimeSlot.count
  end

  test "leaving revokes everything and clears the claim" do
    guest = participants(:planning_guest)

    guest.leave!
    guest.reload

    assert_equal 0, guest.time_slots.count
    assert guest.left_at.present?
    assert guest.declined_at.present?
    assert_nil guest.user_id
    assert_nil guest.token_digest
    assert_nil Participant.find_by_link_token(raw_token(:planning_guest))
  end

  test "a voided guest leaves without a check violation" do
    guest = participants(:planning_guest)
    guest.update_columns(reply_voided_at: Time.current)

    assert_nothing_raised { guest.leave! }

    guest.reload
    assert guest.left_at.present?
    assert guest.declined_at.present?
    assert_nil guest.reply_voided_at
    assert_nil guest.token_digest
  end

  test "time zone must be known" do
    guest = participants(:planning_pending)

    guest.time_zone = "Mars/Olympus"
    assert_not guest.valid?
    guest.time_zone = "Europe/Oslo"
    assert guest.valid?
    guest.time_zone = "UTC"
    assert guest.valid?
  end

  test "addresses_from splits on commas and new lines, normalizes and dedupes" do
    assert_equal %w[bob@example.com cy@example.com], Participant.addresses_from("Bob@Example.com, cy@example.com\nbob@example.com\n\n")
    assert_empty Participant.addresses_from("")
  end

  test "addresses_from names an invalid address and caps the text at four kilobytes" do
    error = assert_raises(Refusal) { Participant.addresses_from("bob@example.com, not-an-address") }
    assert_equal "not-an-address is not a valid email address", error.message

    error = assert_raises(Refusal) { Participant.addresses_from("x" * 4097) }
    assert_equal "The invitation list is too long", error.message
  end

  test "declining clears the slots, takes the guest out of consensus and keeps the link" do
    guest = participants(:planning_guest)

    guest.decline!(time_zone: "Asia/Tokyo")

    assert_empty guest.time_slots
    assert guest.reload.declined_at?
    assert_equal "Asia/Tokyo", guest.time_zone
    assert guest.token_digest?
    assert_empty events(:planning).mutually_available_start_times
  end

  # An offer revision can void a guest between the moment the row is read and
  # the moment the event is locked; every answer must clear it anyway.
  test "an answer clears a void committed after the guest was read" do
    guest = participants(:planning_guest)
    void_elsewhere = -> { Participant.where(id: guest.id).update_all(reply_voided_at: Time.current) }

    void_elsewhere.call
    guest.reply!([ Time.utc(2030, 1, 15, 11) ])
    assert guest.reload.counting?

    void_elsewhere.call
    guest.decline!
    assert_nil guest.reload.reply_voided_at

    guest.update_columns(declined_at: nil)
    void_elsewhere.call
    guest.leave!
    assert guest.reload.left?
    assert_nil guest.reply_voided_at
  end

  test "a reply is older than a revision or a reopen only when that came after it" do
    guest = participants(:planning_guest)
    assert_not guest.replied_before_revision?
    assert_not guest.replied_before_reopen?

    guest.event.offer_revised_at = guest.responded_at + 1.day
    guest.event.reopened_at = guest.responded_at - 1.day
    assert guest.replied_before_revision?
    assert_not guest.replied_before_reopen?

    guest.responded_at = nil
    assert_not guest.replied_before_revision?
  end

  test "a blank address is only blank, not also invalid" do
    guest = events(:planning).participants.guest.new(email: "")

    assert_not guest.valid?
    assert_equal [ "can't be blank" ], guest.errors[:email]
  end

  test "a guest's first answer is confirmed by mail and a later one is not" do
    replier, decliner = participants(:planning_pending), participants(:planning_unsent)

    assert_difference "MailDelivery.response_confirmation.count", 2 do
      replier.reply!([ Time.utc(2030, 1, 15, 10) ])
      decliner.decline!
    end
    assert_equal [ replier.email, decliner.email ].sort, MailDelivery.response_confirmation.pluck(:recipient_email).sort

    assert_no_difference "MailDelivery.response_confirmation.count" do
      replier.reply!([ Time.utc(2030, 1, 15, 11) ])
      replier.decline!
      decliner.reply!([ Time.utc(2030, 1, 15, 10) ])
    end
  end
end
