import { DateTime } from "luxon";

import {
  parseSerializedDateTimes,
  populateTimeZoneSelect,
  slotISO,
} from "./time_zones";
import { allowedDurations } from "../lib/durations";
import { localDateRangeIsAllowed, localDayColumns } from "../lib/time_grid";
import { renderDefinerTable } from "../lib/grid_table";
import {
  attachPainting,
  paintModeControl,
  remapZone,
  rescale,
  seedTabindex,
  summary,
} from "../lib/paint";

const SELECTABLE = ".slot.selectable[data-date]";

// The planned length must be a whole number of slots: lengths that stop
// fitting the step are disabled, and a selection that stopped fitting falls
// back to "Not set" (the blank option).
const syncDurationOptions = (select, stepMinutes) => {
  if (!select) return;
  const options = [...select.options].filter((option) => option.value !== "");
  const { allowed } = allowedDurations(stepMinutes, options.map((option) => option.value));
  const fits = new Set(allowed);
  options.forEach((option) => {
    option.disabled = !fits.has(option.value);
  });
  const chosen = select.options[select.selectedIndex];
  if (chosen && chosen.disabled) select.value = "";
};

const initTimeSlotDefiner = () => {
  const grid = document.querySelector("#time-grid-define");
  if (!grid) return;

  if (grid.__definerAbort) grid.__definerAbort.abort();
  const controller = new AbortController();
  grid.__definerAbort = controller;
  const { signal } = controller;

  const rangeTooltip = document.querySelector("#range-tooltip");
  const timeZonePicker = document.querySelector("#timezone-picker-new");
  const beginDateInput = document.querySelector("#event-begin");
  const endDateInput = document.querySelector("#event-end");
  const timeSlotInput = document.querySelector("#time_slot_array");
  const stepSelect = document.querySelector("#event_slot_minutes");
  const durationSelect = document.querySelector("#event_duration_minutes");
  const summaryElement = document.querySelector("#selection-summary");
  const scrollContainer = grid.closest(".time-grid-scroll");
  const modeControl = paintModeControl(document.querySelector("#paint-mode"), {
    onChange: (mode) => grid.classList.toggle("mode-paint", mode === "paint"),
  });

  let slotMinutes = Number(
    (stepSelect && stepSelect.value) || grid.dataset.slotMinutes || 60,
  );
  let selectedTimeZone = populateTimeZoneSelect(
    timeZonePicker,
    timeZonePicker.dataset.selected || grid.dataset.timeZone,
  );
  const selection = new Set(
    parseSerializedDateTimes(timeSlotInput.value).map(slotISO),
  );
  let rangeStart;
  let rangeEnd;
  let note = "";

  const setSummary = () => {
    if (!summaryElement) return;
    const text = summary(selection, { role: "guest", zone: selectedTimeZone });
    summaryElement.textContent = note ? `${text}. ${note}` : text;
  };

  const serialize = () => {
    timeSlotInput.value = [...selection].sort().join(",");
    setSummary();
  };

  const updateDateRange = () => {
    rangeStart = DateTime.fromISO(beginDateInput.value, { zone: selectedTimeZone }).startOf("day");
    rangeEnd = DateTime.fromISO(endDateInput.value, { zone: selectedTimeZone }).startOf("day");
    const valid = localDateRangeIsAllowed(rangeStart, rangeEnd);
    rangeTooltip.textContent = valid ? "" : "Choose a range from 1 to 31 days.";
    return valid;
  };

  const dropOutsideRange = () => {
    const startMillis = rangeStart.toMillis();
    const endMillis = rangeEnd.plus({ days: 1 }).startOf("day").toMillis();
    let dropped = 0;
    [...selection].forEach((iso) => {
      const millis = DateTime.fromISO(iso).toMillis();
      if (millis < startMillis || millis >= endMillis) {
        selection.delete(iso);
        dropped += 1;
      }
    });
    return dropped;
  };

  const draw = () => {
    grid.replaceChildren();
    if (!updateDateRange()) {
      serialize();
      return;
    }
    const dropped = dropOutsideRange();
    if (dropped > 0) note = `${dropped} outside the dates dropped`;
    renderDefinerTable(grid, localDayColumns(rangeStart, rangeEnd, slotMinutes), {
      selection,
      slotMinutes,
      toISO: slotISO,
    });
    seedTabindex(grid, SELECTABLE);
    serialize();
  };

  const seedDateRange = () => {
    if (selection.size > 0 && !(beginDateInput.value && endDateInput.value)) {
      const instants = [...selection]
        .map((iso) => DateTime.fromISO(iso).setZone(selectedTimeZone))
        .sort((a, b) => a.toMillis() - b.toMillis());
      beginDateInput.value = instants[0].toISODate();
      endDateInput.value = instants[instants.length - 1].toISODate();
      return;
    }
    if (!beginDateInput.value || !endDateInput.value) {
      const today = DateTime.now().setZone(selectedTimeZone).startOf("day");
      beginDateInput.value = today.toISODate();
      endDateInput.value = today.plus({ days: 2 }).toISODate();
    }
  };

  timeZonePicker.addEventListener(
    "change",
    () => {
      const previous = selectedTimeZone;
      selectedTimeZone = timeZonePicker.value;
      const remapped = remapZone(selection, previous, selectedTimeZone);
      selection.clear();
      remapped.forEach((iso) => selection.add(iso));
      note = selection.size > 0 ? `Moved to ${selectedTimeZone} wall clock` : "";
      draw();
    },
    { signal },
  );

  if (stepSelect) {
    stepSelect.addEventListener(
      "change",
      () => {
        const next = Number(stepSelect.value);
        const rescaled = rescale(selection, slotMinutes, next, selectedTimeZone);
        slotMinutes = next;
        grid.dataset.slotMinutes = String(next);
        selection.clear();
        rescaled.forEach((iso) => selection.add(iso));
        syncDurationOptions(durationSelect, next);
        note = "";
        draw();
      },
      { signal },
    );
  }

  [beginDateInput, endDateInput].forEach((input) => {
    input.addEventListener(
      "change",
      () => {
        note = "";
        draw();
      },
      { signal },
    );
  });

  if (timeSlotInput.form) {
    timeSlotInput.form.addEventListener("submit", serialize, { signal });
  }

  attachPainting(grid, {
    selectable: SELECTABLE,
    selection,
    getMode: () => modeControl.get(),
    onStroke: () => {
      note = "";
      serialize();
    },
    scrollContainer,
  });

  syncDurationOptions(durationSelect, slotMinutes);
  seedDateRange();
  draw();
};

export { initTimeSlotDefiner };
