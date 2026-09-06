import { DateTime } from "luxon";

import {
  parseSerializedCounts,
  parseSerializedDateTimes,
  populateTimeZoneSelect,
  slotISO,
} from "./time_zones";
import { offeredGrid } from "../lib/time_grid";
import { renderOfferedTable } from "../lib/grid_table";
import { filterStash } from "../lib/stash";
import { zonedLabel } from "../lib/zoned_label";
import {
  attachPainting,
  paintModeControl,
  seedTabindex,
  summary,
} from "../lib/paint";

const SELECTABLE = ".slot.selectable[data-date]";

const hiddenValue = (selector) => {
  const input = document.querySelector(selector);
  return input ? input.value : "";
};

const initTimeSlotShow = () => {
  const grid = document.querySelector("#time-grid-show");
  if (!grid) return;

  if (grid.__showAbort) grid.__showAbort.abort();
  const controller = new AbortController();
  grid.__showAbort = controller;
  const { signal } = controller;

  const role = grid.dataset.role || "viewer";
  const slotMinutes = Number(grid.dataset.slotMinutes || 60);
  const eventZone = grid.dataset.eventTimeZone || null;
  const finalized = grid.hasAttribute("data-finalized");
  const cancelled = grid.hasAttribute("data-cancelled");
  const durationMinutes = grid.dataset.durationMinutes
    ? Number(grid.dataset.durationMinutes)
    : null;
  const notBefore = grid.dataset.notBefore
    ? DateTime.fromISO(grid.dataset.notBefore)
    : null;

  const offered = parseSerializedDateTimes(hiddenValue("#received-time-slots"));
  const offeredKeys = new Set(offered.map(slotISO));
  const consensusKeys = new Set(
    parseSerializedDateTimes(hiddenValue("#consensus-time-slots")).map(slotISO),
  );
  const mineKeys = new Set(
    parseSerializedDateTimes(hiddenValue("#my-time-slots")).map(slotISO),
  );
  const counts = new Map(
    Object.entries(parseSerializedCounts(hiddenValue("#availability-counts")))
      .map(([iso, count]) => [DateTime.fromISO(iso, { setZone: true }), count])
      .filter(([instant]) => instant.isValid)
      .map(([instant, count]) => [slotISO(instant), Number(count) || 0]),
  );

  const timeZonePicker = document.querySelector("#timezone-picker-show");
  const hideSwitch = document.querySelector("#hide-disabled-cells");
  const summaryElement = document.querySelector("#selection-summary");
  const finalWindowLocal = document.querySelector("#final-window-local");
  const scrollContainer = grid.closest(".time-grid-scroll");
  const modeControl = paintModeControl(document.querySelector("#paint-mode"), {
    onChange: (mode) => grid.classList.toggle("mode-paint", mode === "paint"),
  });
  const targetInput =
    document.querySelector("#new-time-slot-array") ||
    document.querySelector("#final-time-slot-array");
  const targetForm = targetInput ? targetInput.form : null;

  const selectableKeys =
    role === "organizer" ? consensusKeys : role === "guest" ? offeredKeys : new Set();
  const isPast = (instant) => Boolean(notBefore && instant.toMillis() < notBefore.toMillis());

  const stashKey = `catching-app.selection:${window.location.pathname}`;
  const selection = new Set();
  let restored = false;
  try {
    const stashed = window.sessionStorage.getItem(stashKey);
    if (stashed) {
      // Only cells the organizer still offers come back, so a save refused
      // for a removed instant cannot be repeated by the re-apply.
      filterStash(stashed.split(","), offeredKeys).forEach((iso) => selection.add(iso));
      window.sessionStorage.removeItem(stashKey);
      restored = selection.size > 0;
    }
  } catch (_error) {
    // Storage may be unavailable.
  }
  if (!restored && role === "guest") {
    mineKeys.forEach((iso) => {
      if (offeredKeys.has(iso)) selection.add(iso);
    });
  }

  let selectedTimeZone = populateTimeZoneSelect(
    timeZonePicker,
    timeZonePicker.dataset.selected,
  );

  const setSummary = () => {
    if (!summaryElement) return;
    summaryElement.textContent = summary(selection, {
      role: role === "organizer" ? "organizer" : "guest",
      zone: selectedTimeZone,
      slotMinutes,
      durationMinutes,
    });
  };

  const serialize = () => {
    if (targetInput) targetInput.value = [...selection].sort().join(",");
    setSummary();
  };

  const renderFinalWindow = () => {
    if (!finalWindowLocal) return;
    const window_ = parseSerializedDateTimes(hiddenValue("#final-window"));
    if (window_.length < 2) return;
    const [start, end] = window_.map((instant) => instant.setZone(selectedTimeZone));
    finalWindowLocal.textContent = `${start.toFormat("ccc d LLL HH:mm")}–${end.toFormat(
      "HH:mm",
    )} (${selectedTimeZone})`;
  };

  // Every server-rendered instant on the page (derived plan starts, the
  // offer-change and reopen notes, the cancelled stamps) arrives in the
  // event zone; the picker zone replaces it, and a dated label stays dated.
  // An instant the formatter cannot read keeps the server's words.
  const rewriteZonedInstants = () => {
    document.querySelectorAll("time[data-zoned-instant]").forEach((element) => {
      const label = zonedLabel(element.getAttribute("datetime"), selectedTimeZone, {
        format: element.dataset.zonedFormat || "time",
      });
      if (label) element.textContent = label;
    });
  };

  const draw = () => {
    const result = offeredGrid(offered, {
      eventZone,
      viewerZone: selectedTimeZone,
      slotMinutes,
    });
    renderOfferedTable(grid, result, {
      selection,
      selectableKeys,
      consensusKeys,
      counts,
      isPast,
      slotMinutes,
    });
    seedTabindex(grid, SELECTABLE);
    grid.classList.toggle("hide-unoffered", Boolean(hideSwitch && hideSwitch.checked));
    renderFinalWindow();
    rewriteZonedInstants();

    // Every offered instant is behind the cut-off: a guest reads why Save is
    // gone; the organizer's action bar already says so server-side, with
    // the plate that changes the times, so the summary stays quiet.
    const allPast = offered.length > 0 && offered.every(isPast);
    if (allPast && summaryElement && !finalized && !cancelled) {
      summaryElement.textContent = role === "organizer" ? "" : "All the offered times have passed.";
      if (targetForm) {
        targetForm
          .querySelectorAll("[type=submit]")
          .forEach((button) => button.setAttribute("hidden", ""));
        document
          .querySelectorAll(`button[form="${targetForm.id}"]`)
          .forEach((button) => button.setAttribute("hidden", ""));
      }
      if (targetInput) targetInput.value = "";
      return;
    }
    serialize();
  };

  timeZonePicker.addEventListener(
    "change",
    () => {
      selectedTimeZone = timeZonePicker.value;
      draw();
    },
    { signal },
  );

  if (hideSwitch) {
    hideSwitch.addEventListener(
      "change",
      () => grid.classList.toggle("hide-unoffered", hideSwitch.checked),
      { signal },
    );
  }

  document.querySelectorAll("form").forEach((form) => {
    form.addEventListener(
      "submit",
      () => {
        form
          .querySelectorAll('input[name="participant[time_zone]"]')
          .forEach((input) => {
            input.value = timeZonePicker.value;
          });
        if (form === targetForm) {
          serialize();
          try {
            window.sessionStorage.setItem(stashKey, [...selection].join(","));
          } catch (_error) {
            // Ignore storage failures.
          }
        }
      },
      { signal },
    );
  });

  window.addEventListener(
    "pageshow",
    (event) => {
      if (event.persisted) window.location.reload();
    },
    { signal },
  );

  if (!finalized && role !== "viewer") {
    attachPainting(grid, {
      selectable: SELECTABLE,
      selection,
      getMode: () => modeControl.get(),
      onStroke: serialize,
      scrollContainer,
    });
  }

  draw();
};

export { initTimeSlotShow };
