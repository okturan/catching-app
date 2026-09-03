require "test_helper"

class ParticipantTest < ActiveSupport::TestCase
  test "a live token resolves the participant and the digest is all that is stored" do
    guest = participants(:planning_unsent)

    raw = guest.issue_live_token!

    assert_match Participant::TOKEN_FORMAT, raw
    assert_equal Digest::SHA256.hexdigest(raw), guest.reload.token_digest
    assert_equal guest, Participant.find_by_token(raw)
    assert_nil Participant.find_by_token(raw.reverse)
  end

  test "a malformed token runs zero queries" do
    assert_queries_count(0) { assert_nil Participant.find_by_token("short") }
    assert_queries_count(0) { assert_nil Participant.find_by_token(nil) }
  end

  test "trailing punctuation from a mail client is stripped and reported" do
    resolution = Participant.resolve_token("#{raw_token(:planning_guest)}.")

    assert_equal participants(:planning_guest), resolution.participant
    assert_equal raw_token(:planning_guest), resolution.canonical_token
    assert_not resolution.via_pending
  end

  test "a pending token resolves without changing anything until it is promoted" do
    guest = participants(:planning_guest)
    old_raw = raw_token(:planning_guest)

    pending_raw = guest.issue_pending_token!
    resolution = Participant.resolve_token(pending_raw)

    assert resolution.via_pending
    assert_equal guest, resolution.participant
    assert_equal guest, Participant.find_by_token(old_raw)
    assert_nil guest.reload.pending_token_expires_at
    assert_equal users(:invitee).id, guest.user_id

    assert guest.promote_pending!(Participant.digest(pending_raw), actor: nil)
    guest.reload
    assert_equal Participant.digest(pending_raw), guest.token_digest
    assert_nil guest.pending_token_digest
    assert_nil guest.user_id, "promotion by someone other than the claimant clears the claim"
    assert_nil Participant.find_by_token(old_raw)
  end

  test "promotion by the claiming account keeps the claim" do
    guest = participants(:planning_guest)
    pending_raw = guest.issue_pending_token!

    guest.promote_pending!(Participant.digest(pending_raw), actor: users(:invitee))

    assert_equal users(:invitee).id, guest.reload.user_id
  end

  test "an expired organizer recovery token is refused" do
    organizer = participants(:planning_organizer)
    pending_raw = organizer.issue_pending_token!(expires_in: 24.hours)

    assert_equal organizer, Participant.find_by_token(pending_raw)
    travel 25.hours do
      assert_nil Participant.find_by_token(pending_raw)
    end
  end

  test "tokens cannot be issued for a participant who left" do
    left = participants(:planning_left)

    assert_raises(ArgumentError) { left.issue_live_token! }
    assert_raises(ArgumentError) { left.issue_pending_token! }
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

    assert_equal "Guest", guest.display_name(viewer_role: :guest)
    assert_equal "pending@example.com", guest.display_name(viewer_role: :organizer)
    assert_equal "Ian Invitee", participants(:planning_guest).display_name(viewer_role: :guest)
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
  end

  test "one account holds one participation per event" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Participant.transaction(requires_new: true) do
        participants(:planning_pending).update_columns(user_id: users(:owner).id)
      end
    end
  end

  test "deleting an account nullifies participations and keeps the event" do
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
    assert_nil Participant.find_by_token(raw_token(:planning_guest))
    assert_raises(ArgumentError) { participants(:planning_organizer).leave! }
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
end
