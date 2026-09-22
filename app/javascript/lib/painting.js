import { applyStroke, strokeMode } from "./selection";

const EDGE = 48;
const STEP = 12;
const TAP_TOLERANCE = 10;

// Delegated pointer painting for a grid of cells.
//
// - a mouse always paints; touch and pen follow the grid's data-paint-mode,
//   "paint" or "scroll", which the paint-mode controller keeps
// - in paint mode the grid captures the pointer (inside try/catch, synthetic
//   events have no active pointer) and hit-tests with elementFromPoint, so
//   capture is not required for it to work
// - in scroll mode only a pointerdown/pointerup pair on the same cell toggles
// - a stroke ends exactly once on the first of pointerup, pointercancel or
//   lostpointercapture for the active pointer
// - every listener is registered with the caller's AbortSignal, so the
//   controller that attached them takes them all away on disconnect
const attachPainting = (
  grid,
  {
    selectable,
    selection,
    onStroke = () => {},
    scrollContainer = null,
    signal,
  },
) => {
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

  // Only a stroke that has actually moved auto-scrolls. A pointer that goes
  // down inside the 48 px band and never moves is resting, not dragging, and
  // scrolling under it would paint rows the visitor never touched.
  const autoScroll = () => {
    if (!active || !scrollContainer) return;
    if (!active.moved) {
      active.frame = requestAnimationFrame(autoScroll);
      return;
    }
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

      const mode = event.pointerType === "mouse" ? "paint" : grid.dataset.paintMode || "scroll";
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
        moved: false,
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
      if (event.clientX !== active.lastX || event.clientY !== active.lastY) active.moved = true;
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

export { attachPainting, seedTabindex };
