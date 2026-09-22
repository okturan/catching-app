import { Controller } from "@hotwired/stimulus";
import { DateTime } from "luxon";

import { renderOfferedTable } from "../lib/grid_table";
import { attachPainting, seedTabindex } from "../lib/painting";
import { summary } from "../lib/selection";
import { stashSelection, takeStash } from "../lib/stash";
import { offeredGrid } from "../lib/time_grid";
import { zonedLabel } from "../lib/zoned_label";
import { countsByInstant, populateTimeZoneSelect, slotISO, toDateTimes } from "../lib/zones";

const SELECTABLE = ".slot.selectable[data-date]";

// The event page's grid, in the viewer's zone. A guest paints the offered
// times that work, the organizer paints the window to set from the times
// everyone shares, and a finalized or cancelled event is only read. The
// values carry the offer, the viewer's own picks, how many others hold each
// time, the shared times and the set window.
export default class extends Controller {
  static targets = ["grid", "zone", "hideSwitch", "summary", "localWindow", "slots"];
  static values = { offered: Array, mine: Array, counts: Object, consensus: Array, setWindow: Array };

  connect() {
    this.abort = new AbortController();
    const { signal } = this.abort;
    const { dataset } = this.gridTarget;

    this.role = dataset.role || "viewer";
    this.slotMinutes = Number(dataset.slotMinutes || 60);
    this.durationMinutes = dataset.durationMinutes ? Number(dataset.durationMinutes) : null;
    this.notBefore = dataset.notBefore ? DateTime.fromISO(dataset.notBefore) : null;
    this.finalized = this.gridTarget.hasAttribute("data-finalized");
    this.cancelled = this.gridTarget.hasAttribute("data-cancelled");

    this.offered = toDateTimes(this.offeredValue);
    this.offeredKeys = new Set(this.offered.map(slotISO));
    this.consensusKeys = new Set(toDateTimes(this.consensusValue).map(slotISO));
    this.counts = countsByInstant(this.countsValue);
    this.selectableKeys = { organizer: this.consensusKeys, guest: this.offeredKeys }[this.role] || new Set();
    this.selection = this.restoredSelection();
    this.zone = populateTimeZoneSelect(this.zoneTarget, this.zoneTarget.dataset.selected);

    if (!this.finalized && this.role !== "viewer") {
      attachPainting(this.gridTarget, {
        selectable: SELECTABLE,
        selection: this.selection,
        onStroke: () => this.serialize(),
        scrollContainer: this.gridTarget.closest(".time-grid-scroll"),
        signal,
      });
    }

    this.draw();
  }

  disconnect() {
    this.abort.abort();
  }

  rezone() {
    this.zone = this.zoneTarget.value;
    this.draw();
  }

  toggleUnoffered() {
    this.gridTarget.classList.toggle("hide-unoffered", this.hideSwitchTarget.checked);
  }

  // Every form on the page tells the server the zone the viewer reads in.
  // The painting form also keeps its selection for this tab, so a refused
  // save comes back with the paint still on.
  remember({ target: form }) {
    form.querySelectorAll('input[name="participant[time_zone]"]').forEach((input) => {
      input.value = this.zone;
    });
    if (!this.hasSlotsTarget || form !== this.slotsTarget.form) return;

    this.serialize();
    stashSelection(this.stashKey, this.selection);
  }

  // A page restored from the back-forward cache shows a stale grid.
  reloadIfPersisted(event) {
    if (event.persisted) window.location.reload();
  }

  draw() {
    const grid = offeredGrid(this.offered, {
      eventZone: this.gridTarget.dataset.eventTimeZone || null,
      viewerZone: this.zone,
      slotMinutes: this.slotMinutes,
    });
    renderOfferedTable(this.gridTarget, grid, {
      selection: this.selection,
      selectableKeys: this.selectableKeys,
      consensusKeys: this.consensusKeys,
      counts: this.counts,
      isPast: (instant) => this.isPast(instant),
      slotMinutes: this.slotMinutes,
    });
    seedTabindex(this.gridTarget, SELECTABLE);
    this.gridTarget.classList.toggle("hide-unoffered", this.hasHideSwitchTarget && this.hideSwitchTarget.checked);
    this.renderLocalWindow();
    this.rewriteZonedInstants();

    if (this.everyOfferPast()) {
      this.retireSave();
    } else {
      this.serialize();
    }
  }

  serialize() {
    if (this.hasSlotsTarget) this.slotsTarget.value = [...this.selection].sort().join(",");
    this.summaryTarget.textContent = summary(this.selection, {
      role: this.role === "organizer" ? "organizer" : "guest",
      zone: this.zone,
      slotMinutes: this.slotMinutes,
      durationMinutes: this.durationMinutes,
    });
  }

  // A stashed selection from a refused save wins over the saved picks.
  restoredSelection() {
    const restored = takeStash(this.stashKey, this.offeredKeys);
    if (restored.length > 0) return new Set(restored);
    if (this.role !== "guest") return new Set();
    return new Set(toDateTimes(this.mineValue).map(slotISO).filter((iso) => this.offeredKeys.has(iso)));
  }

  get stashKey() {
    return `catching-app.selection:${window.location.pathname}`;
  }

  isPast(instant) {
    return Boolean(this.notBefore && instant.toMillis() < this.notBefore.toMillis());
  }

  everyOfferPast() {
    return this.offered.length > 0 && this.offered.every((instant) => this.isPast(instant)) && !this.finalized && !this.cancelled;
  }

  // Every offered time is behind the cut-off: a guest reads why Save is gone;
  // the organizer's action bar already says so server-side, with the plate
  // that changes the times, so the summary stays quiet.
  retireSave() {
    this.summaryTarget.textContent = this.role === "organizer" ? "" : "All the offered times have passed.";
    if (!this.hasSlotsTarget) return;

    const { form } = this.slotsTarget;
    [...form.querySelectorAll("[type=submit]"), ...this.element.querySelectorAll(`button[form="${form.id}"]`)]
      .forEach((button) => button.setAttribute("hidden", ""));
    this.slotsTarget.value = "";
  }

  renderLocalWindow() {
    if (!this.hasLocalWindowTarget || this.setWindowValue.length < 2) return;
    const [start, end] = toDateTimes(this.setWindowValue).map((instant) => instant.setZone(this.zone));
    this.localWindowTarget.textContent = `${start.toFormat("ccc d LLL HH:mm")}–${end.toFormat("HH:mm")} (${this.zone})`;
  }

  // Every server-rendered instant on the page (derived plan starts, the
  // offer-change and reopen notes, the cancelled stamps) arrives in the
  // event zone; the picker zone replaces it, and a dated label stays dated.
  // An instant the formatter cannot read keeps the server's words.
  rewriteZonedInstants() {
    this.element.querySelectorAll("time[data-zoned-instant]").forEach((element) => {
      const label = zonedLabel(element.getAttribute("datetime"), this.zone, { format: element.dataset.zonedFormat || "time" });
      if (label) element.textContent = label;
    });
  }
}
