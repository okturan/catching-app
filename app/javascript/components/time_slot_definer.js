import moment from "moment-timezone";

const initTimeSlotDefiner = () => {
  if (!document.querySelector("#time-grid-define")) {
    return;
  }

  // Div selectors
  // const beginShow = document.getElementById("begin-show");
  // const endShow = document.getElementById("end-show");
  // const daysShow = document.getElementById("days-show");
  const timeGrid = document.querySelector("#time-grid-define");
  
  // Inputs
  const tzpicker = document.querySelector("#timezone-picker-new");
  const beginDateInput = document.querySelector("#event-begin");
  const endDateInput = document.querySelector("#event-end");

  // Global variables
  let date1;
  let date2;
  let difference;

  // Call all necessary functions
  function drawTimeGrid() {
    timeGrid.innerHTML = "";
    updateDateAndTz();
    fillDays();
    makeRows(25, difference + 1);
  }

  function updateDateAndTz() {
    moment.tz.setDefault(tzpicker.value);
    date1 = moment(beginDateInput.value).startOf("day");
    date2 = moment(endDateInput.value).startOf("day");
    difference = date2.diff(date1, "days");
  }

  // Fill days as headers
  function fillDays() {
    for (let c = 0; c <= difference; c++) {
      let cell = document.createElement("div");
      cell.innerText = moment(date1).format("MMM Do ddd zz");
      timeGrid.appendChild(cell).className = "grid-item header";
      // Fill hour info for each day
      fillHours(date1);
      // Advance onto next day
      date1 = date1.add(1, "day");
    }
  }

  function fillHours(date) {
    for (let i = 0; i < 24; i++) {
      // Create grid cells
      let cell = document.createElement("div");
      cell.innerText = date.format("HH:mm");
      cell.style.gridRow = i + 2;
      timeGrid.appendChild(cell);
      cell.className = "grid-item hour";
      cell.dataset.date = date.toISOString();
      // Increment hour
      date = moment(date).add(1, "hour");
    }
  }

  // Make cells listen for mouseover
  function highlightCell(event) {
    let greenCells = document.querySelectorAll(".active");
    let allCells = document.querySelectorAll(".hour");

    if (event.target.classList.contains("active")) {
      greenCells.forEach((element) => {
        element.addEventListener("mouseover", removeSlots);
      });
    } else {
      allCells.forEach((element) => {
        element.addEventListener("mouseover", addSlots);
      });
    }
  }

  // Actual highlighting and removing
  function addSlots(event) {
    if (!event.target.classList.value.includes("active")) {
      event.target.classList.toggle("active");
    }
  }

  function removeSlots(event) {
    if (event.target.classList.contains("active")) {
      event.target.classList.toggle("active");
    }
  }

  function toggleActive(event) {
    if (event.target.classList.contains("hour")) {
      event.target.classList.toggle("active");
    }
  }

  // Stop cells listening for mouseover
  function resetListeners() {
    let hourInputs = document.querySelectorAll(".hour");
    hourInputs.forEach((element) => {
      element.removeEventListener("mouseover", toggleActive);
      element.removeEventListener("mouseover", addSlots);
      element.removeEventListener("mouseover", removeSlots);
    });
    getActiveCells();
  }

  // Select active cells
  function getActiveCells() {
    let slots = [];
    let activeCells = timeGrid.querySelectorAll(".active");
    activeCells.forEach((cell) => {
      slots.push(cell.dataset.date);
    });
    document.querySelector("#time_slot_array").value = slots;
  }

  // Set a grid columns and rows based on input
  function makeRows(rows, cols) {
    timeGrid.style.setProperty("--grid-rows", rows);
    timeGrid.style.setProperty("--grid-cols", cols);
  }

  // Set a range of 4 days
  function initialDatesSet() {
    date1 = moment().startOf("day");
    date2 = moment(date1).add(4, "day");
    difference = date2.diff(date1, "days");
  }

  function populateTimezones() {
    moment.tz.names().forEach((tzone) => {
      if (tzone == moment.tz.guess()) {
        tzpicker.innerHTML += `<option value="${tzone}" selected>${tzone}</option>`;
      } else {
        tzpicker.innerHTML += `<option value="${tzone}">${tzone}</option>`;
      }
    });
  }

  // Event listeners
  tzpicker.addEventListener("change", drawTimeGrid);
  beginDateInput.addEventListener("change", drawTimeGrid);
  endDateInput.addEventListener("change", drawTimeGrid);
  timeGrid.addEventListener("mousedown", highlightCell);
  timeGrid.addEventListener("mousedown", toggleActive);
  timeGrid.addEventListener("mouseup", resetListeners);

  // Pre fill with values
  populateTimezones();
  moment.tz.setDefault(tzpicker.value);
  initialDatesSet();
  beginDateInput.value = date1.format("Y-MM-DD");
  endDateInput.value = date2.format("Y-MM-DD");
  drawTimeGrid();
};

export { initTimeSlotDefiner };

// TODO
// Date selector ✅
// Set interval between 2 dates (Say Monday to Wednesday) ✅
// Draw 3 columns and 25 rows ✅
// Fill first row with correct date and week day ✅
// Fill hours 1-24 ✅
// Make Cells selectable  ✅
// If initial click box is green remove listener from green Cells and add listener to empty ✅
// If initial click box is empty only add listener to all empty Cells ✅
// Save their state (set id to div) ✅
// Infer timezone from browser ✅
// Make user select it ✅
// Convert ids to UTC based on user timezone ✅
// Convert these states into ranges and post to controller ✅
