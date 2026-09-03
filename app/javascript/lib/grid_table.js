import { cellKey, localSlotLabels } from "./time_grid";

const element = (tag, className) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  return node;
};

const cornerHeader = () => {
  const th = element("th", "row-label-head");
  th.scope = "col";
  th.setAttribute("aria-label", "Time");
  return th;
};

const dayHeader = (day) => {
  const th = element("th");
  th.scope = "col";
  th.textContent = day.toFormat("ccc d LLL");
  const zone = element("small");
  zone.textContent = ` ${day.toFormat("ZZZZ")}`;
  th.appendChild(zone);
  return th;
};

const rowHeader = (label) => {
  const th = element("th");
  th.scope = "row";
  th.textContent = label;
  return th;
};

const placeholder = () => {
  const td = element("td", "slot placeholder");
  td.setAttribute("aria-hidden", "true");
  return td;
};

const cellLabel = (instant, slotMinutes) =>
  `${instant.toFormat("ccc d LLL, HH:mm")}–${instant
    .plus({ minutes: slotMinutes })
    .toFormat("HH:mm")}`;

const makeCell = ({ instant, iso, row, col, slotMinutes, text }) => {
  const td = element("td", "slot");
  td.dataset.date = iso;
  td.dataset.row = String(row);
  td.dataset.col = String(col);
  td.setAttribute("aria-label", cellLabel(instant, slotMinutes));
  td.setAttribute("tabindex", "-1");
  td.textContent = text;
  return td;
};

const buildHead = (grid, days) => {
  const thead = element("thead");
  const tr = element("tr");
  tr.appendChild(cornerHeader());
  days.forEach((day) => tr.appendChild(dayHeader(day)));
  thead.appendChild(tr);
  grid.appendChild(thead);
};

// Definer: every cell of every local day in the range is selectable.
const renderDefinerTable = (grid, columns, { selection, slotMinutes, toISO }) => {
  grid.replaceChildren();
  if (columns.length === 0) return;

  buildHead(grid, columns.map((column) => column.day));
  const labels = columns.map((column) => localSlotLabels(column.slots));
  const rowCount = Math.max(...columns.map((column) => column.slots.length));
  const tbody = element("tbody");

  for (let row = 0; row < rowCount; row += 1) {
    const tr = element("tr");
    const source = columns.findIndex((column) => column.slots[row]);
    tr.appendChild(rowHeader(source >= 0 ? labels[source][row] : ""));

    columns.forEach((column, col) => {
      const slot = column.slots[row];
      if (!slot) {
        tr.appendChild(placeholder());
        return;
      }
      const iso = toISO(slot);
      const cell = makeCell({ instant: slot, iso, row, col, slotMinutes, text: labels[col][row] });
      cell.classList.add("selectable");
      const selected = selection.has(iso);
      cell.classList.toggle("active", selected);
      cell.setAttribute("aria-selected", String(selected));
      tr.appendChild(cell);
    });

    tbody.appendChild(tr);
  }

  grid.appendChild(tbody);
};

// Show grid: the organizer's lattice on a circular band, with offered,
// selectable, past and consensus states and per-cell counts.
const renderOfferedTable = (
  grid,
  result,
  { selection, selectableKeys, consensusKeys, counts, isPast, slotMinutes },
) => {
  grid.replaceChildren();
  if (result.columns.length === 0) return;

  buildHead(grid, result.columns.map((column) => column.day));
  const tbody = element("tbody");

  result.rows.forEach((row, rowIndex) => {
    const tr = element("tr");
    if (row.crossesMidnight) tr.classList.add("day-boundary");
    tr.appendChild(rowHeader(row.label));

    result.columns.forEach((column, colIndex) => {
      const entry = result.cells.get(cellKey(column, row));
      if (!entry) {
        tr.appendChild(placeholder());
        return;
      }

      const cell = makeCell({
        instant: entry.instant,
        iso: entry.iso,
        row: rowIndex,
        col: colIndex,
        slotMinutes,
        text: entry.instant.toFormat("HH:mm"),
      });
      const past = entry.offered && isPast(entry.instant);
      const selectable = selectableKeys.has(entry.iso) && !past;

      cell.classList.toggle("offered", entry.offered);
      cell.classList.toggle("inactive", !entry.offered);
      cell.classList.toggle("past", past);
      cell.classList.toggle("selectable", selectable);
      cell.classList.toggle("consensus", consensusKeys.has(entry.iso));

      if (selectable) {
        const selected = selection.has(entry.iso);
        cell.classList.toggle("active", selected);
        cell.setAttribute("aria-selected", String(selected));
      } else {
        cell.setAttribute("aria-disabled", "true");
      }

      const others = counts.get(entry.iso) || 0;
      if (others > 0) {
        const badge = element("span", "others");
        badge.textContent = `+${others}`;
        cell.appendChild(badge);
        cell.setAttribute(
          "aria-label",
          `${cell.getAttribute("aria-label")}, ${others} other${others === 1 ? "" : "s"} available`,
        );
      }

      tr.appendChild(cell);
    });

    tbody.appendChild(tr);
  });

  grid.appendChild(tbody);
};

export { renderDefinerTable, renderOfferedTable };
