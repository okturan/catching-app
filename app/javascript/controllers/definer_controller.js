import { Controller } from "@hotwired/stimulus";
import { DateTime } from "luxon";

import { removalWarning } from "../lib/definer";
import { renderDefinerTable } from "../lib/grid_table";
import { attachPainting, seedTabindex } from "../lib/painting";
import { remapZone, rescale, summary } from "../lib/selection";
import { localDateRangeIsAllowed, localDayColumns } from "../lib/time_grid";
import { countsByInstant, parseSlotList, populateTimeZoneSelect, slotISO, toDateTimes } from "../lib/zones";

const SELECTABLE = ".slot.selectable[data-date]";
const MORNING_MINUTES = 8 * 60;

// The offer grid of the planning form and of Change the times. There, the
// offer and picked-counts values let the summary name what a removal drops.
export default class extends Controller {
  static targets = ["grid", "slots", "zone", "step", "begin", "end", "rangeNote", "summary"];
  static values = { offer: Array, pickedCounts: Object };

  connect() {
    this.abort = new AbortController();
    const { signal } = this.abort;
    const { dataset } = this.gridTarget;

    this.notBefore = dataset.notBefore ? DateTime.fromISO(dataset.notBefore) : null;
    this.currentOffer = this.hasOfferValue ? toDateTimes(this.offerValue).map(slotISO) : null;
    this.counts = countsByInstant(this.pickedCountsValue);
    this.slotMinutes = Number((this.hasStepTarget && this.stepTarget.value) || dataset.slotMinutes || 60);
    this.zone = populateTimeZoneSelect(this.zoneTarget, this.zoneTarget.dataset.selected || dataset.timeZone);
    this.selection = new Set(parseSlotList(this.slotsTarget.value).map(slotISO));
    this.note = "";

    attachPainting(this.gridTarget, {
      selectable: SELECTABLE,
      selection: this.selection,
      onStroke: () => {
        this.note = "";
        this.serialize();
      },
      scrollContainer: this.gridTarget.closest(".time-grid-scroll"),
      signal,
    });

    this.seedDateRange();
    this.draw();
    this.scrollToWorkingHours();
  }

  disconnect() {
    this.abort.abort();
  }

  // A new zone keeps each painted wall-clock time.
  rezone() {
    const previous = this.zone;
    this.zone = this.zoneTarget.value;
    this.replaceSelection(remapZone(this.selection, previous, this.zone));
    this.draw(`Moved to ${this.zone} wall clock`);
  }

  // Announced, so the planned length can re-fit.
  restep() {
    const next = Number(this.stepTarget.value);
    this.replaceSelection(rescale(this.selection, this.slotMinutes, next, this.zone));
    this.slotMinutes = next;
    this.gridTarget.dataset.slotMinutes = String(next);
    this.draw();
    this.dispatch("restepped", { detail: { slotMinutes: next } });
  }

  redraw() {
    this.draw();
  }

  // Never a disabled button: a blocked one says why and shows the grid.
  submit(event) {
    this.serialize();
    if (this.selection.size > 0) return;

    event.preventDefault();
    this.summaryTarget.textContent = "Paint at least one time before sending";
    this.gridTarget.scrollIntoView({ block: "center", behavior: "instant" });
    this.gridTarget.querySelector('.slot[tabindex="0"]')?.focus();
  }

  // `reason` shows only if something is still selected after the pruning.
  draw(reason = "") {
    this.gridTarget.replaceChildren();
    this.note = "";
    if (!this.updateDateRange()) {
      this.serialize();
      return;
    }
    const dropped = this.dropOutsideRange();
    this.dropPast();
    this.note = [this.selection.size > 0 && reason, dropped > 0 && `${dropped} outside the dates dropped`].filter(Boolean).join(". ");
    renderDefinerTable(this.gridTarget, localDayColumns(this.rangeStart, this.rangeEnd, this.slotMinutes), {
      selection: this.selection,
      slotMinutes: this.slotMinutes,
      toISO: slotISO,
      isPast: (instant) => this.isPast(instant),
      counts: this.counts,
    });
    seedTabindex(this.gridTarget, SELECTABLE);
    this.serialize();
  }

  serialize() {
    this.slotsTarget.value = [...this.selection].sort().join(",");
    const warning = this.removalWarning();
    this.summaryTarget.textContent = [summary(this.selection, { role: "guest", zone: this.zone }), this.note, warning]
      .filter(Boolean).join(". ");
  }

  removalWarning() {
    if (!this.currentOffer) return "";
    const { warning, confirm } = removalWarning(this.currentOffer, this.selection, this.counts);
    if (confirm) this.element.dataset.turboConfirm = confirm;
    else delete this.element.dataset.turboConfirm;
    return warning;
  }

  updateDateRange() {
    this.rangeStart = DateTime.fromISO(this.beginTarget.value, { zone: this.zone }).startOf("day");
    this.rangeEnd = DateTime.fromISO(this.endTarget.value, { zone: this.zone }).startOf("day");
    const valid = localDateRangeIsAllowed(this.rangeStart, this.rangeEnd);
    this.rangeNoteTarget.textContent = valid ? "" : "Choose a range from 1 to 31 days.";
    return valid;
  }

  dropOutsideRange() {
    const startMillis = this.rangeStart.toMillis();
    const endMillis = this.rangeEnd.plus({ days: 1 }).startOf("day").toMillis();
    const outside = [...this.selection].filter((iso) => {
      const millis = DateTime.fromISO(iso).toMillis();
      return millis < startMillis || millis >= endMillis;
    });
    outside.forEach((iso) => this.selection.delete(iso));
    return outside.length;
  }

  // A zone move can push a pick behind the cut-off.
  dropPast() {
    [...this.selection].forEach((iso) => {
      if (this.isPast(DateTime.fromISO(iso))) this.selection.delete(iso);
    });
  }

  isPast(instant) {
    return Boolean(this.notBefore && instant.toMillis() < this.notBefore.toMillis());
  }

  // The grid opens on the earliest painted hour, or on the morning: nobody
  // plans at midnight, and 00:00 at the top hides every useful row.
  scrollToWorkingHours() {
    const box = this.gridTarget.closest(".time-grid-scroll");
    if (!box) return;
    const walls = [...this.selection].map((iso) => {
      const local = DateTime.fromISO(iso).setZone(this.zone);
      return local.hour * 60 + local.minute;
    });
    const minutes = walls.length > 0 ? Math.max(0, Math.min(...walls) - this.slotMinutes) : MORNING_MINUTES;
    const row = this.gridTarget.querySelector(`.slot[data-row="${Math.floor(minutes / this.slotMinutes)}"]`);
    const head = this.gridTarget.querySelector("thead");
    if (row && head) box.scrollTop = row.offsetTop - head.offsetHeight - 4;
  }

  replaceSelection(instants) {
    this.selection.clear();
    instants.forEach((iso) => this.selection.add(iso));
  }

  // The grid opens on the painted days, or on today and the two after it.
  seedDateRange() {
    if (this.beginTarget.value && this.endTarget.value) return;

    if (this.selection.size > 0) {
      const instants = [...this.selection]
        .map((iso) => DateTime.fromISO(iso).setZone(this.zone))
        .sort((a, b) => a.toMillis() - b.toMillis());
      this.beginTarget.value = instants[0].toISODate();
      this.endTarget.value = instants[instants.length - 1].toISODate();
      // An offer inside the grace window starts before today.
      if (this.beginTarget.min && this.beginTarget.value < this.beginTarget.min) {
        this.beginTarget.min = this.beginTarget.value;
      }
    } else {
      const today = DateTime.now().setZone(this.zone).startOf("day");
      this.beginTarget.value = today.toISODate();
      this.endTarget.value = today.plus({ days: 2 }).toISODate();
    }
  }
}
