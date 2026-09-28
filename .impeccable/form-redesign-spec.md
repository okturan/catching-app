# Redesign spec — `app/views/events/new.html.erb`

**Status:** buildable. Every claim below was checked against the code on `guest-first-foundation`. Line references are to the tree as it stands today.

---

## 1. The finding that outranks the brief

At 412 px **the submit button comes before the grid**, and the grid is the only genuinely required input on the page.

`.event-new-grid` collapses to one column at 900 px (`app/assets/stylesheets/components/_events_form.scss:10-12`), the form column is rendered first and `events/_definer_grid` second (`app/views/events/new.html.erb:52`), and `f.submit` is the last child of `.form-events` (`new.html.erb:46`). So a phone visitor scrolls eleven controls, meets "Send me my organizer link", presses it, and gets a 422 reading `Select at least one time slot` (`app/services/time_slot_parser.rb:17`) for an input they never saw. The same fault is the accessibility fault: on **every** viewport the grid comes after the submit in tab order.

Second finding, not in the brief and equally real: **the time zone silently defaults to UTC.** `EventsController#new` builds `Event.new(slot_minutes: 30)`, which picks up the column default `time_zone: "UTC"` (`db/schema.rb`, `t.string "time_zone", default: "UTC", null: false`). `_grid_controls.html.erb:8` passes that into `data-selected="UTC"`, and `populateTimeZoneSelect` keeps a preferred zone whenever it is valid (`app/javascript/components/time_zones.js:22-23`), so the browser-zone fallback **never fires on this page**. Every non-UTC visitor paints the wrong hours until they notice a select nobody pointed them at.

Everything else in the brief is confirmed and addressed below.

---

## 2. The enabling move: hoist the `<form>` to be the two-column grid

Today `simple_form_for` opens *inside* the left column. That is precisely why the grid's four controls are stranded there: `test/controllers/definer_contract_test.rb:34-45` asserts them as **descendants of a form** —

```ruby
assert_select "form select#event_slot_minutes[name='event[slot_minutes]']"
assert_select "form select#timezone-picker-new[name='event[time_zone]'][data-selected]"
assert_select "form input#time_slot_array[name='time_slots[time_slot_array]'][type=hidden]"
assert_select "form input#event-begin[type=date]:not([name])"
assert_select "form input#event-end[type=date]:not([name])"
assert_select "form #range-tooltip[role=status]"
assert_select "form form", count: 0
```

Render `simple_form_for(@event, html: { class: "event-new-grid" })` so the form element *is* `.event-new-grid`, and do the same on the offer page (`form_with ..., id: "offer-form", class: "event-new-grid"`, absorbing the `#offer-edit` div — that id is referenced by no test and no stylesheet). Then the grid panel is inside the form, the controls may move onto the grid, and **`definer_contract_test.rb` passes with no edit at all**. That file is this design's acceptance test.

The alternative — leaving the controls outside the form and wiring them with `form="new_event"`, the pattern already used at `participations/show.html.erb:262` — fails six of those assertions. Hoisting is the mechanism; the `form=` attribute is not.

Hidden inputs (`#time_slot_array`, `#current-offer`, `#guest-picked-counts`, `_method`, CSRF) carry the UA `display: none`, so they never become phantom grid tracks.

**One accepted consequence.** The two `#paint-mode` radios (`name="paint-mode"`) now post. Nothing reads them: `event_params` is an explicit permit list on `params[:event]`, and `organizer_attributes` and `parsed_time_slots` are keyed lookups. Verified harmless on both pages.

---

## 3. Section structure and order

One page. Splitting it would make "controls far from the grid" permanent, would need session state to carry the painted selection, and would cost a stranger a round trip on a phone before they have decided to trust the product — against PRODUCT.md's "fewest steps" and "an email address is enough". Creation is already one atomic `Event.plan!` transaction.

The form has **three direct children**, in DOM order = reading order = tab order at every width.

| | Child | Desktop | Mobile (≤900 px) |
|---|---|---|---|
| 1 | `.form-events` — **"The meeting"** | col 1, row 1 | first |
| 2 | `.time-grid-panel.time-grid-define-wrapper` — **"When could you do it?"** | col 2, rows 1–2 | second |
| 3 | `.form-events` — **"Where do we send your link?"** | col 1, row 2 | third |

The submit is the last thing in child 3, so it is the last thing on the page on a phone and sits at the foot of the left rail on desktop. **No `order` tricks**, so what a screen reader hears is what the eye sees.

The grid panel now carries, top to bottom: `h2`, the paint hint, the `.grid-controls` strip (the shared `_grid_controls` partial), `#range-tooltip`, `.time-grid-scroll` with the table, and the unchanged `.grid-action-bar`.

The page head is unchanged: `h1` "Offer the times you can do." and its lede. No kickers, no plates above headings, two white faces on the wall, the enamel plate submit, Martian Mono only on times. Section headings are Title at 1.2 rem / 800, the low end of DESIGN.md's stated range.

### Layout rule (one rule, both pages)

```scss
.event-new-grid {
  display: grid;
  grid-template-columns: minmax(300px, 420px) minmax(0, 1fr);
  grid-template-rows: auto auto;                 // NEW: makes 1 / -1 resolvable
  gap: clamp(1rem, 3vw, 2.5rem);
  max-width: 1400px;
  margin: 0 auto;
  padding: clamp(1rem, 3vw, 2rem) clamp(1rem, 4vw, 2.5rem) 3rem;
  align-items: start;

  > .form-events    { grid-column: 1; }
  > .time-grid-panel { grid-column: 2; grid-row: 1 / -1; }

  @media (max-width: 900px) {
    grid-template-columns: 1fr;
    grid-template-rows: none;
    > .form-events,
    > .time-grid-panel { grid-column: auto; grid-row: auto; }
  }
}
```

Auto-placement puts face 1 at (1,1) and face 2 at (2,1) around the explicitly placed panel. Below 900 px the rule drops and document order rules.

---

## 4. Every field

Required marking convention: **mark the exception, not the rule.** No asterisks anywhere on this page. Every optional control carries `(optional)` **inside the label text**, so it is announced with the label rather than as a separate glyph. Required controls carry the HTML `required` attribute and `aria-required="true"` and no visible mark. Six things were required and only two were marked (`config/locales/simple_form.en.yml`, `required.mark: '*'`); after this change three text fields plus the grid are required, and nothing is starred.

Mechanically, per input: `required: false, input_html: { required: true, aria: { required: true } }`. That suppresses SimpleForm's mark locally and keeps the native attribute. **Do not** change `config/locales/simple_form.en.yml` or add a global `label_text` — Devise's four views read the same config and keep their asterisks.

Hints are `<p class="form-text" id="…">` and are wired with `aria-describedby`. SimpleForm 5.4.1 does **not** do this for you (verified: no `aria-describedby` anywhere in the gem), so every `f.input` passes `hint_html: { id: … }` and `input_html: { aria: { describedby: … } }`. `Wrappers::Single#html_options` merges `options[:hint_html]` into the `wrap_with` hash, so the id lands on the `.form-text` element.

### Face 1 — "The meeting"

| Label | Control | Required | Help text | Notes |
|---|---|---|---|---|
| **Name** | `f.input :name`, text, maxlength 120 | required | *Your friends see this in the invitation.* | Label kept verbatim. Renaming it to "Name of the meeting" would make `fill_in "Name"` (`organizer_plans_event_test.rb:9`) ambiguous against "Your name" under Capybara's `:smart` fallback, for no real gain — the legend disambiguates. |
| **Description (optional)** | `f.input :description, as: :text`, rows 3, maxlength 2000, placeholder `Do whatever!` | **optional (model change, §6)** | *Anything your friends should know. You can add this later.* | `assert_field "Description"` and `fill_in "Description"` still resolve by substring. |
| **Place (optional)** | `f.input :place`, maxlength 200, placeholder `Ege's place, Kadıköy — or 'Zoom'` | optional | *Where you'll meet, or the app you'll use.* | Placeholder verbatim — pinned by `events_controller_test.rb:30`. |
| **Link (optional)** | `f.input :place_url, as: :url`, maxlength 2000, placeholder `Link to join or a map link` | optional | *A joining link or a map link. It must start with http:// or https://.* | Placeholder verbatim — pinned by `events_controller_test.rb:31`. The hint states `Event::WEB_ADDRESS_MESSAGE`'s rule **before** the visitor breaks it; today it appears only in the 422. |
| **Planned length (optional)** | `select_tag "event[duration_minutes]"`, `id="event_duration_minutes"`, `include_blank: "Not set"` | optional | *How long the meeting itself runs. Lengths that are not a whole number of your slot length are greyed out.* | **Stays in the form, not on the grid.** It is a stored fact guests read in `dl.event-facts` and changing it redraws nothing; and adding it to the shared partial would break `offers_controller_test.rb:94` (`assert_select "[name='event[duration_minutes]']", count: 0` inside `form#offer-form`). Its coupling to slot length gains a voice — see `#duration-note` below. |
| *(status line)* | `<p id="duration-note" class="form-text" role="status">`, empty on load | — | written by JS | New element. Today `syncDurationOptions` (`time_slot_definer.js:36`) silently resets the select to blank when a step change makes the chosen length stop fitting. |

### Child 2 — the grid panel

| Label | Control | Required | Help text |
|---|---|---|---|
| **Slot length** | `select#event_slot_minutes[name="event[slot_minutes]"]`, 15/30/60, default 30 | required, pre-filled | *The size of one cell. Changing it redraws the grid.* |
| **Times shown in** | `select#timezone-picker-new[name="event[time_zone]"][data-selected]` | required, pre-filled | *The grid is drawn in this zone. Your friends see the same hours in theirs.* |
| **First day** | `input#event-begin[type=date]`, unnamed | required, seeded | fieldset hint *Up to 31 days.* |
| **Last day** | `input#event-end[type=date]`, unnamed | required, seeded | shares the fieldset hint and `#range-tooltip` |
| *(the grid)* | `table#time-grid-define[role=grid]` + hidden `#time_slot_array` | **required** | h2 + paint hint, below |
| **Scroll / Paint** | `fieldset#paint-mode[role=radiogroup]` | — | untouched |

Label changes: `"I am in:"` → **"Times shown in"**, `"Start date:"` → **"First day"**, `"End date:"` → **"Last day"**. Colons gone everywhere. "Slot length" is kept **verbatim** — `assert_select "Slot length", selected: "30 minutes"` and `select "60 minutes", from: "Slot length"` are Capybara select-by-label assertions in two system tests. "First day"/"Last day" beats "From"/"To" because each stands alone as an accessible name, and beats "Start date" because *start* collides with `event.start_time`, a different thing this product has.

The two dates sit in `<fieldset><legend class="form-label">Days on the grid</legend>` with `aria-describedby="grid-range-hint range-tooltip"`, so the range reads as one question with one error line.

### Face 3 — "Where do we send your link?" (rendered only when signed out)

| Label | Control | Required | Help text |
|---|---|---|---|
| **Your name** | `input#organizer_name[name="organizer[name]"]`, maxlength 100, `autocomplete="name"` | required | *Your friends see this as the organizer.* |
| **Your email** | `input#organizer_email[name="organizer[email]"][type=email]`, `autocomplete="email"` | required | *We send your organizer link here — it is the only way back into this event.* |

`autocomplete="name"` is new; the email field already has `autocomplete="email"`. The parenthetical sentence comes **out of the label** (a label is the accessible name and is announced on every focus) and becomes persistent help. When `user_signed_in?`, the two fields are replaced by one ink-soft line: **"Planning as Olivia Owner (owner@example.com)."** — today the page says nothing about who will own the event, though `organizer_attributes` (`events_controller.rb:56-63`) has already decided.

### Removed from this page

| Label | Fate |
|---|---|
| **Invite people (one address per line or comma-separated)** | **Deferred** to the organizer page, where the identical control already lives at `participations/show.html.erb:174-178` beside a Send button that actually sends. |

Verified: `create` mails only `Deliveries.organizer_link!` (`events_controller.rb:27`); `assert_equal 0, MailDelivery.invitation.count` (`events_controller_test.rb:69`); guests are created tokenless (`Event.plan!`, `event.rb:77-81`); `events/pending.html.erb:6` already says "Nothing has gone to your guests yet". So the front door asks a stranger for up to 50 of their friends' addresses in exchange for nothing — and imports four failure modes, because `InviteeListParser` raises on one bad address (`invitee_list_parser.rb:15-17`) and that `ArgumentError` 422s and rolls back the entire plan (`events_controller.rb:33-37`). A typo costs the whole form.

**The server is untouched.** `InviteeListParser.call(nil, organizer_email:)` returns `[]`, so the controller, the parser, and `events_controller_test.rb:136-138` ("nope is not a valid email address") all keep working unchanged. Coverage of the invalid-address path already exists independently at `test/controllers/participations/invitations_controller_test.rb:57`.

---

## 5. Copy

| Where | Text |
|---|---|
| h1 (unchanged) | Offer the times you can do. |
| lede (unchanged) | Paint your free hours on the grid, in your own zone. Your friends see them in theirs. |
| Face 1, h2 | **The meeting** |
| Grid panel, h2 | **When could you do it?** |
| Grid panel, paint hint (`#grid-paint-hint`) | Drag across the grid to paint the hours you could do. Drag again to clear. You need at least one. |
| …sentence revealed only under `@media (any-pointer: coarse)` | On a phone, switch to Paint to draw on the grid. Scroll moves the page. |
| Grid controls, fieldset legend | Days on the grid |
| Grid controls, fieldset hint (`#grid-range-hint`) | Up to 31 days. |
| `#range-tooltip` (unchanged string, new position) | Choose a range from 1 to 31 days. |
| Frozen caption on the offer page (unchanged) | Fixed since the first reply |
| `#selection-summary` on load (unchanged) | No times selected |
| `#selection-summary` after a blocked empty submit (new) | Paint at least one time before sending |
| `#duration-note` (new, written by JS) | Planned length cleared: 1 h 30 min is not a whole number of 60-minute slots. |
| Face 3, h2 | **Where do we send your link?** |
| Face 3, paragraph directly above the button | **We email your organizer link to that address. Nothing reaches your friends until you open that link and press Send. Keep the email — that link is how you get back to this event.** |
| Submit, signed out **and signed in** | **Send me my organizer link** |
| Error summary heading (422 only) | **There is a problem** |
| Grid panel h2 on the offer page (local) | The times you offer |

The submit branch at `new.html.erb:46` is deleted. `Deliveries.organizer_link!` runs unconditionally and every organizer lands on "Check your inbox", so **"Plan it" misdescribes its own outcome** for signed-in users. One honest label serves both. Keeping "Send me my organizer link" as the surviving string costs one test edit instead of two.

---

## 6. Description stops being required

Verified: `validates :description, presence: true, length: { maximum: 2000 }` (`event.rb:44`); `db/schema.rb`, `t.text "description", null: false`; `participations/details/edit.html.erb:30` carries `required: true`; the placeholder on the front door is "Do whatever!".

This is the only presence rule on the page with no product justification. It is the second field on the front door of a product positioned as "made for friends, not offices" (PRODUCT.md), the page cannot use it now (no guest exists, no mail leaves), and the organizer can write it later from the details page before a single invitation goes out.

**Change — conservative form, the `NOT NULL` constraint stays:**

1. `app/models/event.rb:44` → `validates :description, length: { maximum: 2000 }`
2. `app/models/event.rb:35` → `normalizes :description, with: ->(description) { description.to_s.strip }, apply_to_nil: true`
3. New migration `change_column_default :events, :description, from: nil, to: ""`, so `Event.new.description` is `""` and the constraint can never be violated by an omitted attribute. `db/schema.rb` updated; `null: false` **kept**.
4. `app/views/participations/details/edit.html.erb:30` → drop `required: true`; line 29 label → `"Description (optional)"`.
5. `app/views/dashboards/shared/_my_events.html.erb:29` → guard with `if event.description.present?` (it prints unconditionally today and would emit an empty `<p>`). `participations/show.html.erb:35` already guards.

---

## 7. Which controls move onto the grid, and how the shared partial still serves the offer page

`app/views/events/_grid_controls.html.erb` keeps every id, name and data attribute. It is **no longer rendered by the two page views**; `app/views/events/_definer_grid.html.erb` renders it, inside `.grid-controls`, directly above the scroll box. `_definer_grid` gains four locals: `frozen:`, `begin_min:`, `heading:`, `hint:`. Both pages call:

```erb
<%= render "events/definer_grid", event: @event, frozen: false, begin_min: nil,
      heading: "When could you do it?", hint: :paint %>
```
```erb
<%= render "events/definer_grid", event: @event, frozen: grid_frozen?, begin_min: @begin_min,
      heading: "The times you offer", hint: :paint %>
```

The frozen branch is untouched: step and zone render `disabled` with `#grid-frozen-note` reading "Fixed since the first reply". Because both forms are hoisted (§2), every `assert_select "form …"` in both `definer_contract_test.rb` and `offers_controller_test.rb:78-96` still resolves.

**One trap, avoided.** `offers_controller_test.rb:83` and `:86` assert `aria-describedby=grid-frozen-note` as an **exact** attribute value. So the new per-control hints are rendered **only when `frozen` is false**, and `described_by` stays mutually exclusive:

```erb
<% described_by = frozen ? "grid-frozen-note" : "slot-minutes-hint" %>
```

Frozen controls are described by the note that explains why they are frozen; live controls by their hint. Zero test edits in this partial.

Zone default fix, in the same partial: `data: { selected: time_zone.to_s }` — with `time_zone` nil that emits `data-selected=""`, which `definer_contract_test.rb:38` (attribute **presence**) still matches, and which `populateTimeZoneSelect` correctly rejects as unknown so the browser zone wins. Paired with `Event.new(slot_minutes: 30, time_zone: nil)` in `EventsController#new`. `events_controller_test.rb:122` asserts the value only on the 422 echo, where the posted zone is present. No behaviour change for a no-JS client: the select already renders empty server-side.

### Offer page, mobile order

Split `participations/offers/edit.html.erb`'s single left column into two `.form-events` faces so the same layout rule fixes the same bug on the second page:

- **Face A** (before the panel): the event name (`.offer-event-name`), the past-times note.
- **Panel**.
- **Face B** (after the panel): the `notice[send]` checkbox, `"Save the new times"`, and the "Back to the event" link.

Every assertion in `offers_controller_test.rb:78-104` is either inside the hoisted form (checkbox, label, submit, all grid controls) or document-wide (`#time-grid-define`, `#selection-summary`, `#paint-mode`, the Back link, `form form` count 0). **No test edits.** The checkbox stays adjacent to the button it modifies.

---

## 8. Errors and validation

### Client — two guards, no `novalidate`

Native validation is **kept**. `required` on the three required text fields plus `type="email"` catches a blank or malformed organizer address before the request, which is faster than a round trip. The one error native validation cannot raise — an empty grid — is now caught in the same place, by extending the submit listener that already exists at `time_slot_definer.js:241-243`:

```js
timeSlotInput.form.addEventListener("submit", (event) => {
  serialize();
  if (selection.size > 0) return;
  event.preventDefault();
  if (summaryElement) summaryElement.textContent = "Paint at least one time before sending";
  grid.scrollIntoView({ block: "center", behavior: "instant" });
  grid.querySelector('.slot[tabindex="0"]')?.focus();
}, { signal });
```

Inside the existing `AbortController` scope, idempotent on `turbo:load`, no new file, no new dependency, no new request. The server check in `Event#replace_time_slots!` (`event.rb:187`) stays the authority; the client guard is a courtesy. The button is never disabled — a disabled primary action with no explanation is worse than a blocked one that says why. The same guard serves the offer page.

`syncDurationOptions` gains the note:

```js
if (chosen && chosen.disabled) {
  select.value = "";
  if (note) note.textContent =
    `Planned length cleared: ${chosen.textContent} is not a whole number of ${stepMinutes}-minute slots.`;
} else if (note) { note.textContent = ""; }
```

### Server — one summary, linked, and no message printed twice

Replace both red boxes (`f.error_notification` at `new.html.erb:9` and the base alert at `:10-12`) with a single error summary as the form's first child, spanning both columns:

```erb
<div class="error-summary" role="alert" tabindex="-1" id="error-summary" data-autofocus>
  <h2>There is a problem</h2>
  <ul>… one <li><a href="#control-id"> per error …</ul>
</div>
```

Focused on render by a new `app/javascript/components/error_summary.js`, called from the existing `turbo:load` block in `application.js:9-13`. It registers no listeners: it focuses the element once and stamps a flag on it, so a Turbo re-render (which replaces the element) re-focuses and a double `turbo:load` does not. No inline script; CSP untouched.

**Link map.** All `:base` messages link to `#time-grid-define` — after the invitee field leaves, every reachable `ArgumentError` on this form comes from `TimeSlotParser`, `replace_time_slots!` or `ensure_aligned!`, so no string matching is needed and none is done. Attribute errors link to their control: `name`→`#event_name`, `description`→`#event_description`, `place`→`#event_place`, `place_url`→`#event_place_url`, `duration_minutes`→`#event_duration_minutes`, `slot_minutes`→`#event_slot_minutes`, `time_zone`→`#timezone-picker-new`. Organizer errors link to `#organizer_name` / `#organizer_email`.

`#time-grid-define` gains `tabindex="-1"` purely as a landing target. A negative tabindex adds no Tab stop, so the availability-grid spec's one-Tab-stop rule still holds exactly. `renderDefinerTable` only calls `grid.replaceChildren()`, so a server-rendered attribute on the table survives every redraw.

**Fix the double message and surface the organizer errors.** Today the rescue re-validates *and* appends `error.message`, so a blank description prints "Validation failed: Description can't be blank" in the box **and** "can't be blank" under the field; and a bad organizer email reaches the visitor only as "Validation failed: Email is invalid" with `#organizer_email` unmarked and unlinked. Replace `events_controller.rb:33-37` with:

```ruby
rescue ActiveRecord::RecordInvalid => error
  render_form_again(record: error.record)
rescue ArgumentError => error
  render_form_again(base: error.message)
end

private

def render_form_again(record: nil, base: nil)
  @event = Event.new(event_params)
  @event.validate
  @event.errors.add(:base, base) if base
  @organizer_errors = record.is_a?(Participant) ? organizer_error_messages(record) : {}
  render :new, status: :unprocessable_entity
end

def organizer_error_messages(record)
  { name: record.errors[:name].first, email: record.errors[:email].first }.compact
end
```

When `error.record` is the Event, `@event.validate` already reproduces its errors, so nothing goes to `:base` and nothing prints twice. `EventsController#new` sets `@organizer_errors = {}`.

Errored controls get `is-invalid`, `aria-invalid="true"`, an `.invalid-feedback d-block` message and their message id appended to `aria-describedby`.

**Every existing controller assertion stays green**, because the summary prints the server's messages verbatim:

- `:97` `must be a web address starting with http:// or https://` — now inline via SimpleForm's `full_error` **and** in the summary.
- `:98` `must be a whole number of 30-minute slots` — inline via the hand-rolled block **and** in the summary.
- `:124` `Time slots must use ISO 8601 timestamps` — base, in the summary.
- `:130` `Select at least one time slot` — base, in the summary.
- `:134` `is not a known time zone` — this one **only** survives because the summary lists attribute errors too; `event[time_zone]` is a hand-rolled `select_tag` that renders no inline error. Do not "simplify" the summary to base errors only.
- `:138` `nope is not a valid email address` — base, in the summary; the server still parses a posted `invitations[emails]`.

`#range-tooltip` keeps `role="status"` (it updates while typing; `alert` would be too loud), keeps its exact string, and simply moves one line above the grid it blanks. Today `draw()` calls `grid.replaceChildren()` and returns on an illegal range (`time_slot_definer.js:157-162`) while the explanation sits a column away.

**Not changed here, deliberately:** the offer page's `.alert-danger` block. `offers_controller_test.rb:313-334` asserts its exact text five times. The error summary is an `events/new` change only.

---

## 9. The 412 px layout

Document order is task order: **The meeting → grid settings → grid → who you are → button.** The submit is now the last element on the page instead of a screenful above the only required input. That single reordering is the most valuable change in this document.

```scss
.grid-controls {
  display: grid;
  gap: 0.75rem;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  margin-bottom: 0.75rem;

  > * { min-width: 0; }
  > .grid-days,
  > .grid-frozen-note,
  > #range-tooltip { grid-column: 1 / -1; }

  .form-select, .form-control { width: 100%; min-width: 0; }
  .form-text { margin-top: 0.25rem; }
}

.grid-days-pair {
  display: grid;
  gap: 0.75rem;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  > * { min-width: 0; }
}

.touch-only { display: none; }
@media (any-pointer: coarse) { .touch-only { display: inline; } }
```

At 412 px the panel's usable width is about `412 − 2×16 (gutter) − 2×12 (panel padding) = 356 px`, so `minmax(180px, 1fr)` yields **one** column — Slot length, then Times shown in, each full width (zone names are long), then First day | Last day two-up at ~172 px each. `min-width: 0` on both the grid item and the input is what stops a native `type=date` control from establishing a floor wider than the viewport; that is the usual cause of horizontal overflow on Android Chrome. Above ~500 px of panel width the strip is two columns, which also suits the offer page. One partial, both pages, no branch.

**Panel height.** `.time-grid-scroll` is `max-height: calc(100dvh - var(--navbar-h) - var(--action-bar-h))`. The toolbar now sits inside the same panel, so add a third term:

```scss
.time-grid-define-wrapper { --grid-controls-h: 240px; }
@media (max-width: 600px) { .time-grid-define-wrapper { --grid-controls-h: 340px; } }
.time-grid-define-wrapper .time-grid-scroll {
  max-height: calc(100dvh - var(--navbar-h) - var(--action-bar-h) - var(--grid-controls-h));
}
```

These are approximations of the toolbar's height, exactly like the existing `--action-bar-h: 96px`; being off by 30 px only makes the scroll box slightly short or tall, never broken. Scoped to `.time-grid-define-wrapper`, so `#time-grid-show` is untouched. Without it the panel exceeds the viewport and the sticky action bar is pushed off screen on a phone.

The touch-only paint sentence is revealed with CSS under `@media (any-pointer: coarse)` — the same mechanism `.paint-mode` already uses at `_time_slot_definer.scss:240-243`. No JS, no pointer sniffing in ERB.

The sticky action bar (`position: sticky; bottom: 0`, coarse pointers) sticks while the grid panel is on screen and releases as face 3 scrolls up past it, because sticky is bounded by its containing block. The submit is newly below it; that must be asserted.

Row heights, the 44/36/28 px touch slot heights, the 88 px touch cell width, `touch-action` and paint mode are all untouched. The grid itself is not redesigned.

---

## 10. Accessibility contract

- **Tab order = DOM order = visual order at both widths:** Name → Description → Place → Link → Planned length → Slot length → Times shown in → First day → Last day → **the grid (one Tab stop)** → Scroll/Paint (coarse only) → Your name → Your email → Send. Today the grid comes after the submit on every viewport; that is the accessibility face of the mobile bug. No `order`, no positive `tabindex`, so WCAG 1.3.2 and 2.4.3 hold without argument.
- **The grid stays exactly one Tab stop** — roving tabindex from `seedTabindex` (`paint.js:303-308`), arrows move, Space toggles, `.slot:focus-visible` outlines in signal red. `#time-grid-define` gains `tabindex="-1"` (landing target only, no Tab stop) and `aria-describedby="grid-paint-hint"`.
- **Heading outline:** one `h1`, then `h2` per section ("The meeting", "When could you do it?", "Where do we send your link?"), each face a `<section aria-labelledby>`. Today the page has an `h1` and nothing else.
- **`<fieldset><legend>Days on the grid</legend>`** around the two dates, because they answer one question together, with `aria-describedby="grid-range-hint range-tooltip"` so the constraint is stated before it is violated. Slot length and Times shown in stay plain labelled selects — no gratuitous nested fieldsets.
- **Labels:** every control has a real `<label for>`. No colons. No explanation inside a label. No placeholder is load-bearing: the two pinned placeholders remain as format examples while their meaning moves into persistent hints, so guidance survives typing and does not depend on grey-on-white contrast.
- **Hints** get ids and are referenced from `aria-describedby` — explicitly, because SimpleForm 5.4.1 renders hints as an unlinked sibling.
- **Errors:** `aria-invalid="true"` on the control, the message id appended to `aria-describedby`, and a `role="alert" tabindex="-1"` summary focused on render whose items are in-page links to the offending controls.
- **Required state** is conveyed by the `required` attribute plus `aria-required="true"`, never by a symbol; `(optional)` is spelled out inside the label so it is announced with it.
- **Live regions unchanged:** `#selection-summary[aria-live=polite]` keeps "No times selected"; `#range-tooltip[role=status]` keeps its string; the new `#duration-note[role=status]` announces the silent planned-length reset. The instruction "You need at least one" lives in static hint text so the live region is not announcing a rule on every stroke.
- **Nothing shrinks:** Bootstrap control heights, the 44 px touch rows and the paint-mode segments are untouched.

---

## 11. Pinned ids — what survives, what changes

**Every pinned id, name and data attribute survives verbatim, and `test/controllers/definer_contract_test.rb` passes with no edit.**

`#time-grid-define[role=grid][data-slot-minutes][data-time-zone][data-not-before]` · `input#time_slot_array[name="time_slots[time_slot_array]"][type=hidden]` · `select#event_slot_minutes[name="event[slot_minutes]"]` · `select#timezone-picker-new[name="event[time_zone]"][data-selected]` · unnamed `input#event-begin[type=date]` and `input#event-end[type=date]` · `#range-tooltip[role=status]` · `#selection-summary[aria-live=polite]` · `fieldset#paint-mode[role=radiogroup]` with two `name=paint-mode` radios · `select#event_duration_minutes[name="event[duration_minutes]"]` · `input#organizer_name[name="organizer[name]"]` · `input#organizer_email[name="organizer[email]"]`. `event_params`, `TimeSlotParams` and every selector in `time_slot_definer.js`, `paint.js`, `grid_table.js`, `time_grid.js` and `durations.js` are untouched.

**New ids** (nothing asserts their absence): `#error-summary`, `#grid-paint-hint`, `#grid-range-hint`, `#slot-minutes-hint`, `#time-zone-hint`, `#duration-note`, `#organizer_email_help`, `#organizer_name_help`, and the classes `.grid-controls`, `.grid-days`, `.grid-days-pair`, `.error-summary`, `.touch-only`, plus the custom property `--grid-controls-h`. `#offer-edit` moves from a div onto the form element.

### Test files that must change

| File & line | Today | Becomes | Why |
|---|---|---|---|
| `test/controllers/events_controller_test.rb:26` | `assert_select "textarea[name='invitations[emails]']"` | `assert_select "textarea[name='invitations[emails]']", count: 0` | the invitee field leaves this page; inverted rather than deleted so the removal stays pinned |
| `test/controllers/events_controller_test.rb:120` | `assert_select "textarea[name='invitations[emails]']", text: /cy@example.com/` | *deleted* | nothing left to echo; `:121` (organizer email echo), `:122` (`data-selected`) and `:123` (`#time_slot_array`) still prove the 422 re-render |
| `test/models/event_test.rb:19` | `test "requires a name, a description, a known zone and an allowed slot length"` | `test "requires a name, a known zone and an allowed slot length"` | description is optional |
| `test/models/event_test.rb:24` | `assert_includes event.errors[:description], "can't be blank"` | *deleted*; add a new case asserting a blank description saves | ditto. Lines 31-33 (the 2000-character limit) stay as they are |
| `test/system/organizer_plans_event_test.rb:12` | `fill_in "Your email (we send your organizer link there)"` | `fill_in "Your email"` | a label is the accessible name and is read on every focus; the sentence belongs in persistent help |
| `test/system/organizer_plans_event_test.rb:13` | `fill_in "Invite people (…)", with: "bob@example.com"` | *deleted* | field deferred |
| `test/system/organizer_plans_event_test.rb:45` | `assert_selector "input[type=submit][value='Send 1 invitation']"` | `assert_selector "input[type=submit][value='Send invitations']"` | with no guest yet, `@counts[:unsent]` is 0 and `participations/show.html.erb:178` renders the plain label |
| `test/system/organizer_plans_event_test.rb:49` | `assert_equal 1, event.guests.count` | insert, before it: `fill_in "Invite more people (one address per line or comma-separated)", with: "bob@example.com"` then `click_button "Send invitations"`; keep the assertion | the test gets longer and now covers the real invitation moment (verify-by-click) instead of a dormant field |
| `test/system/authenticated_ui_test.rb:23` | `assert_field "Invite people (…)"` | *deleted* | field deferred |
| `test/system/authenticated_ui_test.rb:27` | `assert_button "Plan it"` | `assert_button "Send me my organizer link"` | `Deliveries.organizer_link!` runs unconditionally and every organizer lands on "Check your inbox"; "Plan it" misdescribes its own outcome |
| **new** `test/system/organizer_plans_on_touch_test.rb` | — | `MobileSystemTestCase`: visit `new_event_path`; assert `document.documentElement.scrollWidth <= window.innerWidth`; assert `#time-grid-define`'s bounding top is above the submit's; assert the sticky `.grid-action-bar` does not overlap the submit | the definer page has never been checked at 412 px, and this test fails against the page as it stands today, which is the point |

**Deliberately not changed:** `events_controller_test.rb:30-31` (both placeholders kept verbatim); `:136-138` ("nope is not a valid email address" — the server still parses a posted list); the whole of `definer_contract_test.rb`; the whole of `offers_controller_test.rb`; `organizer_paints_with_mouse_test.rb` (it selects the zone by id, `select "Asia/Tokyo", from: "timezone-picker-new"`); `organizer_revises_offer_test.rb`; `guest_paints_on_touch_test.rb`; the labels "Name", "Place", "Link", "Slot length", "Planned length" and the button string "Send me my organizer link".

### Spec scenarios that must change

**`openspec/changes/guest-first-foundation/specs/event-planning/spec.md`**

| Line | Change |
|---|---|
| 8 | Remove `invitations[emails]` from the field list the signed-out GET must contain. |
| 15 | `event[description]` moves from required to bounded only: *"…SHALL require `event[name]` (squished, at most 120 characters), bound `event[description]` (stripped, paragraphs kept, at most 2000 characters), …"* |
| 41 | Drop "the invitee list," from the clause listing what the 422 re-render echoes. |
| 49 | Drop "invitee list" from the echoed values in the scenario. |

The requirement "Invitee lists are parsed, normalized and capped" (lines 25-38) is **unchanged**: the parser is still the live path for `participations/invitations` and still runs, harmlessly, on `POST /events`.

**`openspec/changes/guest-first-foundation/specs/availability-grid/spec.md`**

| Line | Change |
|---|---|
| 7 | `- **WHEN** a keyboard user tabs from the zone picker` → `- **WHEN** a keyboard user tabs from the last grid control`. Documentation correction only — the asserted behaviour (one Tab stop, Space toggles, next Tab leaves) is unchanged, and the current wording is already inaccurate against the shipped DOM, where the zone picker is followed by two date inputs and the submit before the grid is reached. |
| 81 | The bounded-height formula gains its third term: `max-height: calc(100dvh - <navbar> - <action bar> - <grid controls>)` on the definer page. Intent (sticky headers work, auto-scroll has one target) is unchanged. |

The requirement "The definer page keeps its contract" (line 22) needs **no change**: every id, name and data attribute it names still exists, `data-selected` is still present, and hydration after a 422 still works — `#time_slot_array` re-renders from `params.dig(:time_slots, :time_slot_array)` and `seedDateRange()` still reconstructs the range from the hydrated selection by reading the inputs by id.

---

## 12. Implementation checklist

Each step leaves `bin/rails test`, `bin/rails test:system` and `npm test` green on its own.

1. **Zone default.** `EventsController#new` → `Event.new(slot_minutes: 30, time_zone: nil)`; `_grid_controls.html.erb:8` → `data: { selected: time_zone.to_s }`. *Green: `definer_contract_test.rb:38` asserts presence; `events_controller_test.rb:122` asserts the value only on the 422 echo.*
2. **Hoist the form on `events/new`.** `simple_form_for(@event, html: { class: "event-new-grid" })` wraps both columns; delete the two wrapper `<div>`s. Add `grid-template-rows: auto auto` and the two placement rules to `_events_form.scss`. *Green: `definer_contract_test.rb` including `form form` count 0.*
3. **Hoist the form on `offers/edit`.** `form_with ..., id: "offer-form", class: "event-new-grid"` absorbs `#offer-edit`. *Green: `offers_controller_test.rb:78-104`.*
4. **Move the controls onto the grid.** `_definer_grid.html.erb` takes `frozen:`, `begin_min:`, `heading:`, `hint:`; renders the `h2`, the paint hint with its `.touch-only` sentence, `<div class="grid-controls">` around `render "events/grid_controls"`, then the scroll box and the action bar. Both page views drop their own `render "events/grid_controls"` call and pass the new locals. Add `.grid-controls`, `.grid-days-pair`, `.touch-only` and `--grid-controls-h` to `_time_slot_definer.scss`; add `tabindex="-1"` and `aria-describedby="grid-paint-hint"` to the table. *Green: every contract assertion, because the controls are still inside a form.*
5. **Relabel and hint the grid controls.** "Times shown in", "First day", "Last day", the `Days on the grid` fieldset, `#slot-minutes-hint` / `#time-zone-hint` / `#grid-range-hint` rendered **only when `frozen` is false**, `described_by` mutually exclusive. *Green: `offers_controller_test.rb:83,86` keep their exact `aria-describedby=grid-frozen-note`.*
6. **Restructure `events/new` into three children.** Face "The meeting" (Name, Description, Place, Link, Planned length + `#duration-note`), the panel, face "Where do we send your link?" (Your name, Your email, the what-happens-next paragraph, the submit) with the signed-in one-liner. Apply the `(optional)` convention, the hints and their `aria-describedby`, `autocomplete="name"`, and the unified submit copy. *Test edits: `authenticated_ui_test.rb:27`, `organizer_plans_event_test.rb:12`.*
7. **Defer the invitee textarea.** Delete the block at `new.html.erb:39-42`. Server untouched. *Test edits: `events_controller_test.rb:26,120`; `authenticated_ui_test.rb:23`; `organizer_plans_event_test.rb:13,45,49` (+ the new organizer-page invite step). Spec edits: `event-planning/spec.md:8,41,49`.*
8. **Description optional.** Model, normalizer, migration, `details/edit.html.erb:29-30`, `_my_events.html.erb:29`. *Test edits: `event_test.rb:19,24` (+ the new blank-saves case). Spec edit: `event-planning/spec.md:15`.*
9. **Error handling.** Replace `f.error_notification` and the base alert with the linked summary; add `app/javascript/components/error_summary.js` and its call in `application.js`; rewrite the `create` rescue into `render_form_again`; set `@organizer_errors = {}` in `new`; render inline organizer errors with `is-invalid` / `aria-invalid` / `invalid-feedback`. *Green: `events_controller_test.rb:97,98,124,130,134,138,140-142` — check `:134` specifically, it survives only because the summary lists attribute errors too.*
10. **JavaScript guards.** Extend the existing submit listener for an empty selection; write `#duration-note` from `syncDurationOptions`. Both inside the existing `AbortController` scope. *Green: `organizer_plans_event_test.rb` paints before clicking; `organizer_paints_with_mouse_test.rb` and `organizer_revises_offer_test.rb` unaffected.*
11. **Offer page mobile order.** Split the left column into face A (name, past-times note) before the panel and face B (notice checkbox, submit, Back link) after it. *Green: `offers_controller_test.rb` — all its assertions are inside the hoisted form or document-wide.*
12. **Mobile proof.** Add `test/system/organizer_plans_on_touch_test.rb` at 412 px: no horizontal body scroll, grid above the submit, sticky bar clear of the submit. Amend `availability-grid/spec.md:7` and `:81`.

### Explicitly out of scope, and why

**The mail cap discards the visitor's work.** `events_controller.rb:31-32` answers `MailDelivery::CapExceeded` with `redirect_to new_event_path`, losing every typed value and every painted cell — while the rescue immediately below it goes to the trouble of echoing all of them. The fix is `flash.now[:alert] = error.message` plus `render :new, status: :unprocessable_entity`, and it preserves the property the test protects (identical responses for a known and an unknown address, since the body is built entirely from posted params). It is left out of this change because it rewrites `events_controller_test.rb:145-157` — a test that exists to guard an account-enumeration property — and requires editing `event-planning/spec.md:67` ("SHALL respond 303 to the form with the generic alert"). Take it as its own change, on its own review; do not let a form redesign turn a security assertion red.