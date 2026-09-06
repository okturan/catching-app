require "test_helper"

class ParticipationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:planning)
    @guest = participants(:planning_guest)
    @organizer = participants(:planning_organizer)
    @guest_token = raw_token(:planning_guest)
    @organizer_token = raw_token(:planning_organizer)
  end

  test "a guest link renders the show contract without a session" do
    get participation_path(@guest_token)

    assert_response :success
    assert_select 'table#time-grid-show[role=grid][data-role=guest][data-slot-minutes="60"][data-event-time-zone="UTC"]'
    assert_select "#received-time-slots[value=?]", [ "2030-01-15T10:00:00Z", "2030-01-15T11:00:00Z" ].to_json
    assert_select "#my-time-slots[value=?]", [ "2030-01-15T10:00:00Z" ].to_json
    assert_select "#availability-counts"
    assert_select "form#availability-form[action=?]", participation_path(@guest_token)
    assert_select "button[form=availability-form]", "Save"
    assert_select "a[href=?]", participation_claim_path(@guest_token), count: 0, text: "Keep this event in your account"
    assert_no_match "pending@example.com", response.body
  end

  test "the card answers where and how long only when the organizer set them" do
    @event.activities.delete_all
    get participation_path(@guest_token)
    assert_select "dl.event-facts", count: 0
    assert_select "a.plate-button-sm", text: "Edit details", count: 0

    assert_select "#time-grid-show[data-duration-minutes]", count: 0

    @event.update!(place: "Ege's place, Kadıköy", place_url: "https://zoom.us/j/1?pwd=secret", duration_minutes: 120)
    get participation_path(@guest_token)

    assert_response :success
    assert_select "#time-grid-show[data-duration-minutes='120']"
    assert_select ".event-panel dl.event-facts", count: 1 do
      assert_select "dt", count: 2
      assert_select "dt", text: "Where"
      assert_select "dt", text: "How long"
      assert_select ".plate", count: 0
      assert_select "dd", text: /Ege's place, Kadıköy/
      assert_select "dd", text: "2 h"
      assert_select "a.quiet-link[target=_blank][rel=?][href=?]", "noopener noreferrer nofollow", "https://zoom.us/j/1?pwd=secret", count: 1 do
        assert_select "span.visually-hidden", text: "(opens in a new tab)"
      end
      assert_equal "zoom.us", css_select("a.quiet-link").first.children.first.text.strip
    end
    assert_equal 1, response.body.scan("zoom.us/j/1").size, "the full link appears only in the anchor's href"
    assert_select "a[href=?]", edit_participation_details_path(@guest_token), count: 0

    @event.update_columns(slot_minutes: 30)
    @event.update!(place: nil, place_url: nil, duration_minutes: 90)
    get participation_path(@guest_token)
    assert_select "dl.event-facts dt", count: 1, text: "How long"
    assert_select "dl.event-facts dd", text: "1 h 30 min"
  end

  test "the organizer sees Edit details in both families while pending or finalized" do
    get participation_path(@organizer_token)
    assert_select ".event-panel a.plate-button-sm[href=?]", edit_participation_details_path(@organizer_token), text: "Edit details"

    sign_in users(:owner)
    get my_participation_path(@organizer)
    assert_select "a.plate-button-sm[href=?]", edit_my_participation_details_path(@organizer), text: "Edit details"

    get participation_path(raw_token(:finalized_organizer))
    assert_select "a.plate-button-sm[href=?]", edit_participation_details_path(raw_token(:finalized_organizer)), text: "Edit details"

    @event.update_columns(cancelled_at: Time.current)
    get participation_path(@organizer_token)
    assert_select "a[href=?]", edit_participation_details_path(@organizer_token), count: 0
  end

  test "every participant reads the plan in order on the card, with no times while pending" do
    @event.activities.create!(name: "Dune", duration: 155, position: 1, description: "Part one only")
    @event.activities.create!(name: "Credits", position: 2)

    get participation_path(@guest_token)

    assert_response :success
    assert_select ".event-panel dl.event-facts", count: 1 do
      assert_select "dt", count: 1, text: "Plan"
      assert_select ".plate", count: 0
      assert_select "dd ol.event-plan li", count: 3
      assert_select "li .event-plan-note", count: 1, text: "Part one only"
      assert_select "time[data-zoned-instant]", count: 0
    end
    assert_equal [ "Board games · 1 h 30 min", "Dune · 2 h 35 min", "Credits" ],
      css_select("ol.event-plan li .event-plan-item").map(&:text)
    assert_select "a[href*=activities]", count: 0

    get participation_path(@organizer_token)
    assert_select "ol.event-plan li", count: 3

    sign_in users(:invitee)
    get my_participation_path(@guest)
    assert_select "ol.event-plan li", count: 3

    sign_in users(:outsider)
    get my_participation_path(@guest)
    assert_response :not_found
    assert_no_match "Part one only", response.body
  end

  test "derived starts appear once the time is set, in the event zone, and stop after an item without a length" do
    finalized = events(:finalized)
    finalized.update_columns(time_zone: "Europe/Berlin", start_time: Time.utc(2030, 1, 15, 19), end_time: Time.utc(2030, 1, 15, 22))
    pizza = finalized.activities.create!(name: "Pizza", duration: 30, position: 0)
    dune = finalized.activities.create!(name: "Dune", duration: 155, position: 1)
    token = raw_token(:finalized_guest)

    get participation_path(token)

    assert_response :success
    assert_select "ol.event-plan li", count: 2
    assert_select "ol.event-plan li:nth-child(1) time.time[data-zoned-instant][datetime=?]", "2030-01-15T19:00:00Z", text: "20:00 (Europe/Berlin)"
    assert_select "ol.event-plan li:nth-child(2) time.time[data-zoned-instant][datetime=?]", "2030-01-15T19:30:00Z", text: "20:30 (Europe/Berlin)"

    finalized.activities.create!(name: "Arrive", position: 0)
    pizza.update!(position: 1)
    dune.update!(position: 2)
    get participation_path(token)
    assert_equal [ "Arrive", "Pizza · 30 min", "Dune · 2 h 35 min" ], css_select("ol.event-plan li .event-plan-item").map(&:text)
    assert_select "ol.event-plan time[data-zoned-instant]", count: 1
    assert_select "ol.event-plan li:nth-child(1) time[data-zoned-instant][datetime=?]", "2030-01-15T19:00:00Z"

    finalized.update_columns(cancelled_at: Time.current)
    get participation_path(token)
    assert_select "ol.event-plan li", count: 3
    assert_select "ol.event-plan time[data-zoned-instant]", count: 0
  end

  test "another account's participation leaks no place link" do
    @event.update!(place_url: "https://zoom.us/j/1?pwd=secret")
    sign_in users(:outsider)

    get my_participation_path(@guest)

    assert_response :not_found
    assert_select "#link-not-found"
    assert_no_match "zoom.us", response.body
  end

  test "capability pages carry cache, index and canonical hygiene" do
    get participation_path(@guest_token)

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select 'meta[name="robots"][content="noindex"]'
    assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
    assert_select 'meta[property="og:url"][content=?]', root_url
  end

  test "unknown, short and left tokens are one friendly 404 that points at the newest email" do
    [ "b" * 32, "short", raw_token(:planning_left) ].each do |token|
      get participation_path(token)
      assert_response :not_found
      assert_select "#link-not-found a[href=?]", new_organizer_link_path
      assert_select "#link-not-found h1", text: "This link is not valid."
      assert_select "#link-not-found p", text: "Open the newest email about this event: a newer link replaces older ones, or ask the organizer to resend your invitation."
    end
  end

  test "the organizer sees Tell the guests only while a change has not reached anyone with a link" do
    get participation_path(@organizer_token)
    assert_response :success
    assert_select ".event-untold", count: 0
    assert_select "form[action=?]", participation_notice_path(@organizer_token), count: 0

    @event.update_columns(revision: 2, notified_revision: 1)
    get participation_path(@organizer_token)
    assert_select ".event-untold[role=status]", count: 1 do
      assert_select "span", text: "Guests have not been told about your latest changes."
      assert_select "form.event-untold-form[action=?][method=post]", participation_notice_path(@organizer_token) do
        assert_select "button[type=submit].plate-button-sm", text: "Tell the guests"
      end
    end
    assert_select "h1 .plate", count: 0

    sign_in users(:owner)
    get my_participation_path(@organizer)
    assert_select "form.event-untold-form[action=?]", my_participation_notice_path(@organizer)

    get participation_path(@guest_token)
    assert_select ".event-untold", count: 0

    @event.guests.update_all(token_digest: nil)
    get participation_path(@organizer_token)
    assert_select ".event-untold", count: 0

    @event.participants.update_all(token_digest: nil)
    @event.update_columns(cancelled_at: Time.current)
    sign_in users(:owner)
    get my_participation_path(@organizer)
    assert_select ".event-untold", count: 0
  end

  test "an invitation tells the guest the current state, so nothing is left untold" do
    @event.guests.where.not(id: participants(:planning_unsent).id).update_all(token_digest: nil, user_id: nil)
    @event.update_details!(place: "Zoom")
    assert_equal [ 1, 0 ], [ @event.reload.revision, @event.notified_revision ]

    post participation_invitations_path(@organizer_token)
    assert_response :redirect

    get participation_path(@organizer_token)
    assert_response :success
    assert_select ".event-untold", count: 0
    assert_equal 1, @event.reload.notified_revision
  end

  test "a resend to one guest does not hide a change the other linked guests were never told about" do
    @event.update_details!(place: "Zoom")
    assert_equal [ 1, 0 ], [ @event.reload.revision, @event.notified_revision ]
    assert_equal 2, @event.guests.active.linked.count

    post participation_participant_resend_path(@organizer_token, @guest)
    assert_redirected_to participation_path(@organizer_token)
    assert_equal "Invitation sent again to invitee@example.com.", flash[:notice]

    get participation_path(@organizer_token)
    assert_response :success
    assert_select ".event-untold", count: 1
    assert_equal 0, @event.reload.notified_revision
  end

  test "a guest who replied before the reopen reads that the set time was withdrawn, zoned and named, until they save" do
    @event.update_columns(time_zone: "Europe/Berlin", reopened_at: Time.utc(2025, 1, 10, 19), reopen_count: 1)
    @guest.update_columns(responded_at: Time.utc(2025, 1, 2, 9))

    get participation_path(@guest_token)

    assert_response :success
    assert_select "table#time-grid-show[data-role=guest]:not([data-finalized])"
    assert_select "#availability-form"
    assert_select "#my-time-slots[value=?]", [ "2030-01-15T10:00:00Z" ].to_json
    assert_select "button[form=availability-form]", "Save"
    assert_select ".grid-action-bar .grid-notice[role=status]", count: 1 do
      assert_select "time.time[data-zoned-instant][data-zoned-format='date-time'][datetime=?]", "2025-01-10T19:00:00Z", text: "Fri 10 Jan 2025 20:00 (Europe/Berlin)"
    end
    assert_equal "The set time was withdrawn on Fri 10 Jan 2025 20:00 (Europe/Berlin). Check your picks and save.", css_select(".grid-notice").first.text.squish
    assert_select ".event-reopened", { count: 0 }, "the count note is the organizer's"

    patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
    assert_redirected_to participation_path(@guest_token)
    assert_operator @guest.reload.responded_at, :>, @event.reopened_at
    get participation_path(@guest_token)
    assert_select ".grid-notice", count: 0

    get participation_path(raw_token(:planning_pending))
    assert_select ".grid-notice", { count: 0 }, "a guest who never replied sees no note"

    get participation_path(@organizer_token)
    assert_select ".grid-notice", text: /withdrawn/, count: 0
    assert_select ".event-reopened" do
      assert_select "span", text: "Reopened once"
      assert_select "time.time[data-zoned-instant][datetime=?]", "2025-01-10T19:00:00Z", text: "Fri 10 Jan 2025 20:00 (Europe/Berlin)"
    end

    @guest.update_columns(responded_at: Time.utc(2025, 1, 2, 9))
    @event.update_columns(offer_revised_at: Time.utc(2025, 1, 11, 9), offer_revision_added: 1, offer_revision_removed: 0)
    get participation_path(@guest_token)
    assert_select ".grid-notice", count: 1, text: /changed the offered times/
    assert_no_match "withdrawn", css_select(".grid-action-bar").first.text

    @event.update_columns(reopened_at: Time.utc(2025, 1, 12, 9))
    get participation_path(@guest_token)
    assert_select ".grid-notice", count: 1, text: /The set time was withdrawn/
  end

  test "a guest whose every offered time has passed reads so with no Save control, before any script runs" do
    past = 3.days.ago.beginning_of_hour
    @event.time_slots.where(start_time: Time.utc(2030, 1, 15, 10)).update_all(start_time: past)
    @event.time_slots.where(start_time: Time.utc(2030, 1, 15, 11)).update_all(start_time: past - 1.hour)

    get participation_path(@guest_token)

    assert_response :success
    assert_select "#selection-summary", text: "All the offered times have passed."
    assert_select "button[form=availability-form][hidden]", text: "Save"
    assert_select "#availability-form"

    get participation_path(@organizer_token)
    assert_select ".grid-every-past" do
      assert_select "span", text: "Every offered time has passed."
      assert_select "a.plate-button-sm[href=?]", edit_participation_offer_path(@organizer_token), text: "Change the times"
    end
    assert_select "#selection-summary", text: "No times selected"
  end

  test "a guest who replied before a revision reads what changed, in the event zone and named" do
    @event.update_columns(time_zone: "Europe/Berlin", offer_revised_at: Time.utc(2030, 1, 10, 19), offer_revision_added: 4, offer_revision_removed: 1)
    @guest.update_columns(responded_at: Time.utc(2030, 1, 2, 9))

    get participation_path(@guest_token)

    assert_response :success
    assert_select ".grid-action-bar .grid-notice[role=status]", count: 1 do
      assert_select "time.time[data-zoned-instant][data-zoned-format='date-time'][datetime=?]", "2030-01-10T19:00:00Z", text: "Thu 10 Jan 2030 20:00 (Europe/Berlin)"
    end
    notice = css_select(".grid-notice").first.text.squish
    assert_equal "The organizer changed the offered times on Thu 10 Jan 2030 20:00 (Europe/Berlin): 4 added, 1 removed. Check your picks and save again.", notice
    assert_select "#my-time-slots[value=?]", [ "2030-01-15T10:00:00Z" ].to_json
    assert_select "button[form=availability-form]", "Save"

    @guest.update_columns(responded_at: Time.utc(2030, 1, 11, 9))
    get participation_path(@guest_token)
    assert_select ".grid-notice", count: 0

    get participation_path(raw_token(:planning_pending))
    assert_select ".grid-notice", { count: 0 }, "a guest who never replied sees no notice"

    get participation_path(@organizer_token)
    assert_select ".grid-notice", text: /changed the offered times/, count: 0
  end

  test "a voided guest is asked to pick again with nothing pre-painted, and saving un-voids without a second confirmation" do
    @event.update_columns(offer_revised_at: 2.days.ago, offer_revision_added: 0, offer_revision_removed: 1)
    @guest.update_columns(responded_at: 3.days.ago, reply_voided_at: 2.days.ago)
    @guest.time_slots.delete_all

    get participation_path(@guest_token)
    assert_response :success
    assert_select ".grid-action-bar .grid-notice[role=status]", text: "None of the times you picked are offered any more. Pick again."
    assert_select "#my-time-slots[value=?]", [].to_json
    assert_select "button[form=availability-form]", "Save"

    assert_no_difference "MailDelivery.count" do
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
    end
    assert_redirected_to participation_path(@guest_token)
    assert_equal "Availability saved.", flash[:notice]
    @guest.reload
    assert_nil @guest.reply_voided_at
    assert_nil @guest.declined_at
    assert_in_delta Time.current, @guest.responded_at, 5.seconds
    assert @guest.counting?

    follow_redirect!
    assert_select ".grid-notice", count: 0
  end

  test "a voided guest declines or leaves without a check violation and the notice is gone" do
    @guest.update_columns(reply_voided_at: Time.current)

    post participation_decline_path(@guest_token)
    assert_redirected_to participation_path(@guest_token)
    @guest.reload
    assert @guest.declined_at.present?
    assert_nil @guest.reply_voided_at
    follow_redirect!
    assert_select ".grid-notice", count: 0

    @guest.update_columns(declined_at: nil, reply_voided_at: Time.current)
    delete participation_path(@guest_token)
    assert_response :see_other
    @guest.reload
    assert @guest.left_at.present?
    assert_nil @guest.reply_voided_at
  end

  test "a declined guest hears about additions only" do
    @guest.update_columns(responded_at: Time.utc(2030, 1, 2, 9), declined_at: Time.utc(2030, 1, 2, 9))
    @guest.time_slots.delete_all
    @event.update_columns(offer_revised_at: Time.utc(2030, 1, 10), offer_revision_added: 2, offer_revision_removed: 1)

    get participation_path(@guest_token)
    assert_select ".grid-action-bar .grid-notice[role=status]", text: "You said none of these worked. New times were added."

    @event.update_columns(offer_revision_added: 0, offer_revision_removed: 1)
    get participation_path(@guest_token)
    assert_select ".grid-notice", count: 0
  end

  test "a save carrying an instant the organizer removed is refused and writes nothing" do
    @event.revise_offer!(starts_at: [ Time.utc(2030, 1, 15, 10) ])

    patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z,2030-01-15T11:00:00Z" } }

    assert_response :see_other
    assert_equal "Select only time slots offered by the organizer", flash[:alert]
    assert_equal [ Time.utc(2030, 1, 15, 10) ], @guest.time_slots.reload.pluck(:start_time)
  end

  test "the organizer table and summary name who has not answered the current times" do
    pending = participants(:planning_pending)
    pending.update_columns(responded_at: Time.utc(2030, 1, 5, 9))
    @event.replace_time_slots!(participant: pending, starts_at: [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ])
    @event.update_columns(offer_revised_at: Time.utc(2030, 1, 10), offer_revision_added: 1, offer_revision_removed: 1)
    @guest.update_columns(responded_at: Time.utc(2030, 1, 2, 9), reply_voided_at: Time.utc(2030, 1, 10))
    @guest.time_slots.delete_all

    get participation_path(@organizer_token)

    assert_response :success
    assert_select "#participant-table td", text: "needs a new reply"
    assert_select "#participant-table td", text: "replied (2 slots, before the last change)"
    assert_select ".event-people", text: /2 invited,\s+1 replied,\s+0 cannot make it,\s+1 not yet invited,\s+1 replied before the last change,\s+1 need a new reply/
    assert_select ".grid-action-bar .grid-notice[role=status]", text: "2 guests have not answered the current times"
    assert_select "button[form=finalize-form]", text: "Set in stone"
    assert_select "table#time-grid-show[data-role=organizer]"

    pending.update_columns(responded_at: Time.utc(2030, 1, 11, 9))
    get participation_path(@organizer_token)
    assert_select "#participant-table td", text: "replied (2 slots)"
    assert_select ".grid-notice", text: "1 guest has not answered the current times"
    assert_select ".event-people", text: /before the last change/, count: 0

    pending.update_columns(reply_voided_at: Time.utc(2030, 1, 10))
    pending.time_slots.delete_all
    get participation_path(@organizer_token)
    assert_select ".grid-notice", text: "2 guests have not answered the current times"
    assert_select "button[form=finalize-form]", count: 0
    assert_select ".grid-action-bar", text: /No one has answered the current times yet\./
    assert_select "table#time-grid-show[data-role=organizer]"
    post participation_finalization_path(@organizer_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_response :see_other
    assert_equal "Wait for at least one reply before confirming", flash[:alert]

    @guest.update_columns(reply_voided_at: nil)
    @event.replace_time_slots!(participant: @guest, starts_at: [ Time.utc(2030, 1, 15, 10) ])
    @guest.update_columns(responded_at: Time.utc(2030, 1, 11, 9))
    pending.update_columns(reply_voided_at: nil, declined_at: Time.utc(2030, 1, 12))
    get participation_path(@organizer_token)
    assert_select ".grid-notice", count: 0
    assert_select "#participant-table td", text: "none of these work"
    assert_select "#participant-table td", text: "replied (1 slot)"
  end

  test "when every offered time has passed the organizer is sent to change the times and the guest cannot save" do
    past = [ 3.days.ago, 2.days.ago ].map { |t| t.utc.beginning_of_hour }
    @event.time_slots.delete_all
    now = Time.current
    TimeSlot.insert_all!(past.map { |t| { participant_id: @organizer.id, event_id: @event.id, start_time: t, created_at: now, updated_at: now } })

    get participation_path(@organizer_token)

    assert_response :success
    assert_select ".grid-action-bar .grid-every-past", count: 1 do
      assert_select "span", text: "Every offered time has passed."
      assert_select "a.plate-button-sm[href=?]", edit_participation_offer_path(@organizer_token), text: "Change the times"
    end
    assert_select "button[form=finalize-form]", count: 0
    assert_select ".grid-notice", count: 0
    assert_select "#time-grid-show[data-not-before]"

    get participation_path(@guest_token)
    assert_select ".grid-every-past", count: 0
    assert_select "button[form=availability-form]", { text: "Save", count: 1 }, "the JavaScript hides Save once it reads data-not-before"
  end

  test "a mangled link is sent to its canonical path" do
    get "/p/#{@guest_token}."

    assert_response :see_other
    assert_redirected_to participation_path(@guest_token)
  end

  test "a guest saves availability and the first reply is recorded" do
    patch participation_path(@guest_token), params: {
      time_slots: { time_slot_array: "2030-01-15T11:00:00Z" },
      participant: { name: "  Ian   Invitee ", time_zone: "Europe/Berlin" }
    }

    assert_redirected_to participation_path(@guest_token)
    assert_equal "Availability saved.", flash[:notice]
    assert_equal [ Time.utc(2030, 1, 15, 11) ], @guest.time_slots.reload.pluck(:start_time)
    assert_equal "Europe/Berlin", @guest.reload.time_zone
    assert_equal "Ian Invitee", @guest.name
    assert_equal [ Time.utc(2030, 1, 15, 10), Time.utc(2030, 1, 15, 11) ],
      @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
  end

  test "guest save errors redirect with the exact message and change nothing" do
    existing = @guest.time_slots.order(:start_time).pluck(:start_time)

    cases = {
      "" => "Select at least one time slot",
      "2030-01-20T09:00:00Z" => "Select only time slots offered by the organizer",
      "2030-01-15T10:30:00Z" => "Select time slots on the event's 60-minute grid",
      "invalid" => "Time slots must use ISO 8601 timestamps"
    }
    cases.each do |value, message|
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: value } }
      assert_response :see_other
      assert_equal message, flash[:alert], "for #{value.inspect}"
    end

    patch participation_path(@guest_token), params: {
      time_slots: { time_slot_array: "2030-01-15T10:00:00Z" }, participant: { time_zone: "Mars/Olympus" }
    }
    assert_response :see_other
    assert_match(/time zone/i, flash[:alert])

    assert_equal existing, @guest.time_slots.reload.order(:start_time).pluck(:start_time)
  end

  test "a finalized event refuses guest writes" do
    patch participation_path(raw_token(:finalized_guest)), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }

    assert_response :see_other
    assert_equal "Availability is closed for this event", flash[:alert]
  end

  test "a finalized guest page keeps Leave and drops the paint and decline forms" do
    token = raw_token(:finalized_guest)

    get participation_path(token)

    assert_response :success
    assert_select "table#time-grid-show[data-role=viewer][data-finalized]:not([data-cancelled])"
    assert_select "#availability-form", count: 0
    assert_select "button[form=availability-form]", count: 0
    assert_select "form[action=?]", participation_decline_path(token), count: 0
    assert_select "form[action=?] input[name=_method][value=delete]", participation_path(token)
    assert_select "button", text: "Leave this event"
    assert_select "h1 span.plate", text: "Set in stone"
    assert_select ".event-panel a.plate-button-sm[href=?]", participation_calendar_path(token), text: "Add to calendar"
  end

  test "an organizer token cannot use guest actions" do
    offer = @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)

    patch participation_path(@organizer_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_response :not_found
    post participation_decline_path(@organizer_token)
    assert_response :not_found
    delete participation_path(@organizer_token)
    assert_response :not_found

    assert_equal offer, @event.time_slots.where(participant_id: @organizer.id).order(:start_time).pluck(:start_time)
  end

  test "a guest declines and can change their mind" do
    post participation_decline_path(@guest_token), params: { participant: { time_zone: "Asia/Tokyo" } }

    assert_redirected_to participation_path(@guest_token)
    @guest.reload
    assert @guest.declined_at.present?
    assert_equal 0, @guest.time_slots.count
    assert_equal "Asia/Tokyo", @guest.time_zone
    assert_empty @event.mutually_available_start_times

    patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_nil @guest.reload.declined_at
  end

  test "a guest leaves for good" do
    delete participation_path(@guest_token)

    assert_redirected_to root_path
    assert_response :see_other
    assert_equal "You left Planning session.", flash[:notice]
    @guest.reload
    assert @guest.left_at.present?
    assert_nil @guest.user_id
    assert_nil @guest.token_digest

    get participation_path(@guest_token)
    assert_response :not_found

    sign_in users(:invitee)
    get my_participation_path(@guest)
    assert_response :not_found
  end

  test "a pending token changes nothing on GET and is promoted by its first write" do
    pending = @guest.issue_pending_token!

    get participation_path(pending)
    assert_response :success
    get participation_path(@guest_token)
    assert_response :success
    assert_equal Participant.digest(@guest_token), @guest.reload.token_digest
    assert_equal users(:invitee).id, @guest.user_id

    patch participation_path(pending), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_redirected_to participation_path(pending)
    @guest.reload
    assert_equal Participant.digest(pending), @guest.token_digest
    assert_nil @guest.pending_token_digest
    assert_nil @guest.user_id, "a write by someone who is not the claimant clears the claim"

    get participation_path(@guest_token)
    assert_response :not_found
  end

  test "promotion by the claiming account keeps the claim" do
    pending = @guest.issue_pending_token!
    sign_in users(:invitee)

    patch participation_path(pending), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }

    assert_equal users(:invitee).id, @guest.reload.user_id
  end

  test "the session family needs a session, ignores query tokens and hides other accounts" do
    get my_participation_path(@guest)
    assert_redirected_to new_user_session_path

    get my_participation_path(@guest, token: @guest_token)
    assert_redirected_to new_user_session_path

    patch my_participation_path(@guest), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    assert_redirected_to new_user_session_path

    sign_in users(:outsider)
    get my_participation_path(@guest)
    assert_response :not_found

    sign_in users(:invitee)
    get my_participation_path(@guest)
    assert_response :success
    assert_select "form#availability-form[action=?]", my_participation_path(@guest)
    assert_select "a", text: /activit/i, count: 0
    assert_no_match "/events/#{@event.id}/activities", response.body

    patch my_participation_path(@guest), params: { time_slots: { time_slot_array: "2030-01-15T11:00:00Z" } }
    assert_redirected_to my_participation_path(@guest)
    assert_equal [ Time.utc(2030, 1, 15, 11) ], @guest.time_slots.reload.pluck(:start_time)
  end

  test "the token family ignores a participation_id query parameter" do
    get participation_path(@guest_token, participation_id: participants(:other_organizer).id)

    assert_response :success
    assert_select "table#time-grid-show[data-role=guest]"
  end

  test "the organizer link is opened only through the token family" do
    event = Event.plan!(
      attributes: { name: "Fresh", description: "new", slot_minutes: 30, time_zone: "UTC" },
      organizer: { email: users(:owner).email, name: users(:owner).full_name, user: users(:owner) },
      starts_at: [ Time.utc(2031, 5, 1, 9) ],
      invitee_emails: [ "someone@example.com" ]
    )
    organizer = event.organizer
    live = organizer.issue_live_token!

    sign_in users(:owner)
    get my_participation_path(organizer)
    assert_response :success
    assert_nil organizer.reload.link_opened_at
    assert_select "input[type=submit][value^=Send]", count: 0
    assert_match "Open the organizer link we emailed to owner@example.com", response.body

    post my_participation_invitations_path(organizer)
    assert_response :see_other
    assert_match(/Open the organizer link/, flash[:alert])
    assert_nil event.guests.first.reload.token_digest

    get participation_path(live)
    assert_response :success
    assert organizer.reload.link_opened_at.present?
    assert_select "input[type=submit][value=?]", "Send 1 invitation"
  end

  test "raw tokens never reach the request log" do
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)
    begin
      get participation_path(@guest_token)
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "invalid" } }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_match "/p/[FILTERED]", io.string
    assert_no_match @guest_token, io.string
  end

  test "writes through one token are rate limited as a courtesy" do
    with_rate_limit_count(31) do
      patch participation_path(@guest_token), params: { time_slots: { time_slot_array: "2030-01-15T10:00:00Z" } }
    end

    assert_response :too_many_requests
  end
end
