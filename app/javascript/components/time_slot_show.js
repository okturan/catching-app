import { DateTime } from "luxon";

import {
  browserTimeZone,
  parseSerializedDateTimes,
  populateTimeZoneSelect,
  slotISO,
} from "./time_zones";
import {
  localDayColumns,
  localHourLabels,
  timeGridDimensions,
} from "../lib/time_grid";

const initTimeSlotShow = () => {
  const timeGrid = document.querySelector("#time-grid-show");
  if (!timeGrid) return;

  const receivedTimeSlots = document.querySelector("#received-time-slots");
  const guestTimeSlots = document.querySelector("#guest-time-slots");
  const consensusTimeSlots = document.querySelector("#consensus-time-slots");
  const timeZonePicker = document.querySelector("#timezone-picker-show");
  const disableCheckbox = document.querySelector("#hide-disabled-cells");
  const isHost = document.querySelector("#is-host").value === "yes";

  let selectedTimeZone = browserTimeZone;

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

  const cellsByTime = () =>
    new Map(
      [...timeGrid.querySelectorAll(".hour")].map((cell) => [
        cell.dataset.date,
        cell,
      ]),
    );

  const markReceivedCells = (slots) => {
    const cells = cellsByTime();
    slots.forEach((slot) => cells.get(slotISO(slot))?.classList.add("received"));

    timeGrid.querySelectorAll(".hour:not(.received)").forEach((cell) => {
      cell.classList.add("inactive");
    });
  };

  const markGuestCells = (slots) => {
    const cells = cellsByTime();
    slots.forEach((slot) => {
      cells.get(slotISO(slot))?.insertAdjacentText("afterbegin", "🙋");
    });
  };

  const clearStoredSelections = () => {
    ["#new-time-slot-array", "#final-time-slot-array"].forEach((selector) => {
      const input = document.querySelector(selector);
      if (input) input.value = "";
    });
  };

  const drawTimeGrid = () => {
    timeGrid.replaceChildren();
    clearStoredSelections();
    disableCheckbox.checked = false;

    const hostSlots = parseSerializedDateTimes(receivedTimeSlots.value);
    if (hostSlots.length === 0) return;

    const firstDay = DateTime.min(...hostSlots)
      .setZone(selectedTimeZone)
      .startOf("day");
    const lastDay = DateTime.max(...hostSlots)
      .setZone(selectedTimeZone)
      .startOf("day");
    const columns = localDayColumns(firstDay, lastDay);
    const dimensions = timeGridDimensions(columns);

    fillDays(columns);
    makeRows(dimensions.rows, dimensions.columns);
    const selectableSlots = isHost
      ? parseSerializedDateTimes(consensusTimeSlots.value)
      : hostSlots;
    markReceivedCells(selectableSlots);
    markGuestCells(parseSerializedDateTimes(guestTimeSlots.value));
  };

  const addSlots = (event) => {
    if (event.target.matches(".hour:not(.inactive)")) {
      event.target.classList.add("active");
    }
  };

  const removeSlots = (event) => {
    if (event.target.matches(".hour:not(.inactive)")) {
      event.target.classList.remove("active");
    }
  };

  const highlightCell = (event) => {
    if (!event.target.matches(".hour:not(.inactive)")) return;

    const handler = event.target.classList.contains("active")
      ? removeSlots
      : addSlots;

    timeGrid.querySelectorAll(".hour:not(.inactive)").forEach((cell) => {
      cell.addEventListener("mouseover", handler);
    });
  };

  const toggleActive = (event) => {
    if (event.target.matches(".hour:not(.inactive)")) {
      event.target.classList.toggle("active");
    }
  };

  const activeSlots = () =>
    [...timeGrid.querySelectorAll(".hour.active")].map(
      (cell) => cell.dataset.date,
    );

  const storeGuestSlots = () => {
    const input = document.querySelector("#new-time-slot-array");
    if (input) input.value = activeSlots().join(",");
  };

  const storeFinalSlots = () => {
    const input = document.querySelector("#final-time-slot-array");
    if (input) input.value = activeSlots().join(",");
  };

  const resetListeners = () => {
    timeGrid.querySelectorAll(".hour").forEach((cell) => {
      cell.removeEventListener("mouseover", addSlots);
      cell.removeEventListener("mouseover", removeSlots);
    });
    storeGuestSlots();
  };

  if (isHost) {
    timeGrid.addEventListener("mousedown", toggleActive);
    timeGrid.addEventListener("mouseup", storeFinalSlots);
  } else {
    timeGrid.addEventListener("mousedown", highlightCell);
    timeGrid.addEventListener("mousedown", toggleActive);
    timeGrid.addEventListener("mouseup", resetListeners);
  }

  disableCheckbox.addEventListener("change", (event) => {
    timeGrid.querySelectorAll(".hour.inactive").forEach((cell) => {
      cell.classList.toggle("disabled", event.target.checked);
    });
  });

  timeZonePicker.addEventListener("change", () => {
    selectedTimeZone = timeZonePicker.value;
    drawTimeGrid();
  });

  selectedTimeZone = populateTimeZoneSelect(timeZonePicker);
  drawTimeGrid();
};

export { initTimeSlotShow };
