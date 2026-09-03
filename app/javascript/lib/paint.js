import { DateTime } from "luxon";

const strokeMode = (cellSelected) => (cellSelected ? "remove" : "add");

const applyStroke = (selection, iso, mode) => {
  if (mode === "add") {
    selection.add(iso);
  } else {
    selection.delete(iso);
  }
  return selection;
};

const toISO = (dateTime) => dateTime.toUTC().toISO();
const parseISO = (iso) => DateTime.fromISO(iso, { setZone: true });

// Moves every selected instant so that it keeps its wall clock in the new
// zone: 09:00 Europe/Berlin becomes 09:00 Asia/Kolkata.
const remapZone = (selection, fromZone, toZone) =>
  new Set(
    [...selection].map((iso) =>
      toISO(
        parseISO(iso).setZone(fromZone).setZone(toZone, { keepLocalTime: true }),
      ),
    ),
  );

// Refining expands each slot into its sub-cells; coarsening snaps each slot
// to the coarser grid anchored at local midnight in the given zone.
const rescale = (selection, fromMinutes, toMinutes, zone) => {
  const rescaled = new Set();

  for (const iso of selection) {
    const instant = parseISO(iso).setZone(zone);

    if (toMinutes < fromMinutes) {
      for (let offset = 0; offset < fromMinutes; offset += toMinutes) {
        rescaled.add(toISO(instant.plus({ minutes: offset })));
      }
    } else {
      const startOfDay = instant.startOf("day");
      const minutes = instant.diff(startOfDay, "minutes").minutes;
      const snapped = Math.floor(minutes / toMinutes) * toMinutes;
      rescaled.add(toISO(startOfDay.plus({ minutes: snapped })));
    }
  }

  return rescaled;
};

const formatDuration = (minutes) => {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${rest} min`;
  if (rest === 0) return `${hours} h`;
  return `${hours} h ${rest} min`;
};

const summary = (selection, { role = "guest", zone = "UTC", slotMinutes = 60 } = {}) => {
  const instants = [...selection]
    .map((iso) => parseISO(iso).setZone(zone))
    .filter((instant) => instant.isValid)
    .sort((a, b) => a.toMillis() - b.toMillis());

  if (instants.length === 0) return "No times selected";

  if (role === "organizer") {
    const contiguous = instants.every(
      (instant, index) =>
        index === 0 ||
        instant.diff(instants[index - 1], "minutes").minutes === slotMinutes,
    );
    if (!contiguous) return "Not one continuous window";

    const start = instants[0];
    const end = instants[instants.length - 1].plus({ minutes: slotMinutes });
    return `${start.toFormat("ccc d LLL HH:mm")}–${end.toFormat("HH:mm")} (${formatDuration(
      instants.length * slotMinutes,
    )})`;
  }

  const days = new Set(instants.map((instant) => instant.toISODate())).size;
  return `${instants.length} slot${instants.length === 1 ? "" : "s"} on ${days} day${
    days === 1 ? "" : "s"
  }`;
};

const EDGE = 48;
const STEP = 12;
const TAP_TOLERANCE = 10;

// Delegated pointer painting for a grid of cells.
//
// - a mouse always paints; touch and pen follow getMode(): "paint" or "scroll"
// - in paint mode the grid captures the pointer (inside try/catch, synthetic
//   events have no active pointer) and hit-tests with elementFromPoint, so
//   capture is not required for it to work
// - in scroll mode only a pointerdown/pointerup pair on the same cell toggles
// - a stroke ends exactly once on the first of pointerup, pointercancel or
//   lostpointercapture for the active pointer
// - listeners are registered through an AbortController stored on the
//   element so re-running on every turbo:load is idempotent
const attachPainting = (
  grid,
  {
    selectable,
    selection,
    getMode = () => "paint",
    onStroke = () => {},
    scrollContainer = null,
  },
) => {
  if (grid.__paintAbort) grid.__paintAbort.abort();
  const controller = new AbortController();
  grid.__paintAbort = controller;
  const { signal } = controller;

  let active = null;
  let tap = null;

  const cellAt = (x, y) => {
    const element = document.elementFromPoint(x, y);
    const cell = element && element.closest(selectable);
    return cell && grid.contains(cell) ? cell : null;
  };

  const paintCell = (cell, mode) => {
    const iso = cell.dataset.date;
    if (!iso) return;
    const selected = mode === "add";
    if (cell.classList.contains("active") === selected) return;
    cell.classList.toggle("active", selected);
    cell.setAttribute("aria-selected", String(selected));
    applyStroke(selection, iso, mode);
  };

  const toggleCell = (cell) =>
    paintCell(cell, strokeMode(cell.classList.contains("active")));

  const stopAutoScroll = () => {
    if (active && active.frame) cancelAnimationFrame(active.frame);
  };

  const autoScroll = () => {
    if (!active || !scrollContainer) return;
    const rect = scrollContainer.getBoundingClientRect();
    let dx = 0;
    let dy = 0;
    if (active.lastY > rect.bottom - EDGE) dy = STEP;
    else if (active.lastY < rect.top + EDGE) dy = -STEP;
    if (active.lastX > rect.right - EDGE) dx = STEP;
    else if (active.lastX < rect.left + EDGE) dx = -STEP;
    if (dx || dy) {
      scrollContainer.scrollBy(dx, dy);
      const cell = cellAt(active.lastX, active.lastY);
      if (cell) paintCell(cell, active.mode);
    }
    active.frame = requestAnimationFrame(autoScroll);
  };

  const endStroke = () => {
    if (!active) return;
    stopAutoScroll();
    active = null;
    grid.classList.remove("painting");
    onStroke();
  };

  grid.addEventListener(
    "pointerdown",
    (event) => {
      if (!event.isPrimary) return;
      const cell = event.target.closest(selectable);
      if (!cell || !grid.contains(cell)) return;

      const mode = event.pointerType === "mouse" ? "paint" : getMode();
      if (mode === "scroll") {
        tap = { pointerId: event.pointerId, cell, x: event.clientX, y: event.clientY };
        return;
      }

      if (active) return;
      active = {
        pointerId: event.pointerId,
        mode: strokeMode(cell.classList.contains("active")),
        lastX: event.clientX,
        lastY: event.clientY,
        frame: null,
      };
      grid.classList.add("painting");
      paintCell(cell, active.mode);
      try {
        grid.setPointerCapture(event.pointerId);
      } catch (_error) {
        // Synthetic events have no active pointer to capture.
      }
      if (scrollContainer) active.frame = requestAnimationFrame(autoScroll);
    },
    { signal },
  );

  grid.addEventListener(
    "pointermove",
    (event) => {
      if (!active || event.pointerId !== active.pointerId) return;
      active.lastX = event.clientX;
      active.lastY = event.clientY;
      const cell = cellAt(event.clientX, event.clientY);
      if (cell) paintCell(cell, active.mode);
    },
    { signal },
  );

  const finish = (event) => {
    if (active && event.pointerId === active.pointerId) {
      endStroke();
      return;
    }
    if (tap && event.pointerId === tap.pointerId) {
      const pending = tap;
      tap = null;
      if (event.type !== "pointerup") return;
      const moved = Math.hypot(event.clientX - pending.x, event.clientY - pending.y);
      const cell = cellAt(event.clientX, event.clientY);
      if (moved < TAP_TOLERANCE && cell === pending.cell) {
        toggleCell(cell);
        onStroke();
      }
    }
  };

  ["pointerup", "pointercancel", "lostpointercapture"].forEach((type) => {
    grid.addEventListener(type, finish, { signal });
  });

  // Keyboard: roving tabindex, arrows move between cells, Space toggles.
  const cellsIn = () => [...grid.querySelectorAll(".slot[data-row][data-col]")];
  const focusCell = (cell) => {
    cellsIn().forEach((other) => other.setAttribute("tabindex", "-1"));
    cell.setAttribute("tabindex", "0");
    cell.focus();
  };
  grid.addEventListener(
    "keydown",
    (event) => {
      const cell = event.target.closest(".slot[data-row][data-col]");
      if (!cell) return;
      const row = Number(cell.dataset.row);
      const col = Number(cell.dataset.col);
      const moves = {
        ArrowUp: [row - 1, col],
        ArrowDown: [row + 1, col],
        ArrowLeft: [row, col - 1],
        ArrowRight: [row, col + 1],
      };
      if (event.key === " " || event.key === "Enter") {
        if (cell.matches(selectable)) {
          toggleCell(cell);
          onStroke();
        }
        event.preventDefault();
        return;
      }
      if (!(event.key in moves)) return;
      const [nextRow, nextCol] = moves[event.key];
      const next = grid.querySelector(
        `.slot[data-row="${nextRow}"][data-col="${nextCol}"]`,
      );
      if (next) focusCell(next);
      event.preventDefault();
    },
    { signal },
  );
  grid.addEventListener(
    "focusin",
    (event) => {
      const cell = event.target.closest(".slot[data-row][data-col]");
      if (cell) {
        cellsIn().forEach((other) => other.setAttribute("tabindex", "-1"));
        cell.setAttribute("tabindex", "0");
      }
    },
    { signal },
  );

  return { abort: () => controller.abort(), toggleCell };
};

// Seeds the roving tabindex: the first selectable cell is the Tab stop.
const seedTabindex = (grid, selectable) => {
  const cells = [...grid.querySelectorAll(".slot[data-row][data-col]")];
  cells.forEach((cell) => cell.setAttribute("tabindex", "-1"));
  const first = cells.find((cell) => cell.matches(selectable)) || cells[0];
  if (first) first.setAttribute("tabindex", "0");
};

// Paint/Scroll control for coarse pointers. Remembers the choice.
const paintModeControl = (
  element,
  { storageKey = "catching-app.paint-mode", onChange = () => {} } = {},
) => {
  let mode = "scroll";
  try {
    const stored = window.localStorage.getItem(storageKey);
    if (stored === "paint" || stored === "scroll") mode = stored;
  } catch (_error) {
    // Storage may be unavailable; scroll stays the default.
  }

  const inputs = element ? [...element.querySelectorAll("input[type=radio]")] : [];
  const sync = () => {
    inputs.forEach((input) => {
      input.checked = input.value === mode;
    });
    if (element) element.dataset.mode = mode;
    onChange(mode);
  };
  inputs.forEach((input) => {
    input.addEventListener("change", () => {
      if (!input.checked) return;
      mode = input.value === "paint" ? "paint" : "scroll";
      try {
        window.localStorage.setItem(storageKey, mode);
      } catch (_error) {
        // Ignore storage failures.
      }
      sync();
    });
  });
  sync();

  return { get: () => mode };
};

export {
  applyStroke,
  attachPainting,
  paintModeControl,
  remapZone,
  rescale,
  seedTabindex,
  strokeMode,
  summary,
};
