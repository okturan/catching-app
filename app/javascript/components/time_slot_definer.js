import { DateTime } from "luxon";

import {
  browserTimeZone,
  populateTimeZoneSelect,
  slotISO,
} from "./time_zones";
import {
  localDateRangeIsAllowed,
  localDayColumns,
  localHourLabels,
  timeGridDimensions,
} from "../lib/time_grid";

const initTimeSlotDefiner = () => {
  const timeGrid = document.querySelector("#time-grid-define");
  if (!timeGrid) return;

  const rangeTooltip = document.querySelector("#range-tooltip");
  const timeZonePicker = document.querySelector("#timezone-picker-new");
  const beginDateInput = document.querySelector("#event-begin");
  const endDateInput = document.querySelector("#event-end");
  const timeSlotInput = document.querySelector("#time_slot_array");

  let selectedTimeZone = browserTimeZone;
  let rangeStart;
  let rangeEnd;

  const updateDateRange = () => {
    rangeStart = DateTime.fromISO(beginDateInput.value, {
      zone: selectedTimeZone,
    }).startOf("day");
    rangeEnd = DateTime.fromISO(endDateInput.value, {
      zone: selectedTimeZone,
    }).startOf("day");

    const validRange = localDateRangeIsAllowed(rangeStart, rangeEnd);

    rangeTooltip.textContent = validRange
      ? ""
      : "Choose a range from 1 to 31 days.";

    return validRange;
  };

  const makeRows = (rows, columns) => {
    timeGrid.style.setProperty("--grid-rows", rows);
    timeGrid.style.setProperty("--grid-cols", columns);
  };

  const fillHours = (column, columnIndex) => {
    const labels = localHourLabels(column.hours);

    column.hours.forEach((hour, hourIndex) => {
      const cell = document.createElement("div");
      cell.textContent = labels[hourIndex];
      cell.style.gridColumn = columnIndex + 1;
      cell.style.gridRow = hourIndex + 2;
      cell.className = "grid-item hour";
      cell.dataset.date = slotISO(hour);
      timeGrid.appendChild(cell);
    });
  };

  const fillDays = (columns) => {
    columns.forEach((column, columnIndex) => {
      const header = document.createElement("div");
      header.textContent = column.day.toFormat("MMM d ccc ZZZZ");
      header.style.gridColumn = columnIndex + 1;
      header.className = "grid-item header";
      timeGrid.appendChild(header);
      fillHours(column, columnIndex);
    });
  };

  const drawTimeGrid = () => {
    timeGrid.replaceChildren();
    timeSlotInput.value = "";

    if (!updateDateRange()) return;

    const columns = localDayColumns(rangeStart, rangeEnd);
    const dimensions = timeGridDimensions(columns);
    fillDays(columns);
    makeRows(dimensions.rows, dimensions.columns);
  };

  const addSlots = (event) => {
    if (event.target.classList.contains("hour")) {
      event.target.classList.add("active");
    }
  };

  const removeSlots = (event) => {
    if (event.target.classList.contains("hour")) {
      event.target.classList.remove("active");
    }
  };

  const highlightCell = (event) => {
    if (!event.target.classList.contains("hour")) return;

    const handler = event.target.classList.contains("active")
      ? removeSlots
      : addSlots;

    timeGrid.querySelectorAll(".hour").forEach((cell) => {
      cell.addEventListener("mouseover", handler);
    });
  };

  const toggleActive = (event) => {
    if (event.target.classList.contains("hour")) {
      event.target.classList.toggle("active");
    }
  };

  const storeActiveCells = () => {
    const slots = [...timeGrid.querySelectorAll(".hour.active")].map(
      (cell) => cell.dataset.date,
    );
    timeSlotInput.value = slots.join(",");
  };

  const resetListeners = () => {
    timeGrid.querySelectorAll(".hour").forEach((cell) => {
      cell.removeEventListener("mouseover", addSlots);
      cell.removeEventListener("mouseover", removeSlots);
    });
    storeActiveCells();
  };

  timeZonePicker.addEventListener("change", () => {
    selectedTimeZone = timeZonePicker.value;
    drawTimeGrid();
  });
  beginDateInput.addEventListener("change", drawTimeGrid);
  endDateInput.addEventListener("change", drawTimeGrid);
  timeGrid.addEventListener("mousedown", highlightCell);
  timeGrid.addEventListener("mousedown", toggleActive);
  timeGrid.addEventListener("mouseup", resetListeners);

  selectedTimeZone = populateTimeZoneSelect(timeZonePicker);
  rangeStart = DateTime.now().setZone(selectedTimeZone).startOf("day");
  rangeEnd = rangeStart.plus({ days: 2 });
  beginDateInput.value = rangeStart.toISODate();
  endDateInput.value = rangeEnd.toISODate();
  drawTimeGrid();
};

export { initTimeSlotDefiner };
