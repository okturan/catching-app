const initTimeSlotDefiner = () => {
  if (!document.getElementById("submit-slots")) {
    return;
  }

  // Div selectors
  const submitButton = document.getElementById("submit-slots");
  const beginShow = document.getElementById("begin-show");
  const endShow = document.getElementById("end-show");
  const daysShow = document.getElementById("days-show");
  const calendar = document.getElementById("calendar");

  // Inputs
  const searchList = document.getElementById("timezone-picker");
  const beginDateInput = document.querySelector("#event-begin");
  const endDateInput = document.querySelector("#event-end");

  // Global variables
  let date1;
  let date2;
  let difference;

  // Create a grid based on the number of days between dates
  function makeRows(rows, cols) {
    calendar.style.setProperty("--grid-rows", rows);
    calendar.style.setProperty("--grid-cols", cols);
  }

  // Fill days as headers
  function fillDays() {
    for (c = 0; c <= difference; c++) {
      let options = {
        weekday: "long",
        month: "short",
        day: "numeric",
        timeZone: `${searchList.value}`,
      };
      let cell = document.createElement("div");
      cell.innerText = date1.toLocaleString("en-Tr", options);
      calendar.appendChild(cell).className = "grid-header";
      // Fill hour info for each day
      fillHours(date1);
      // Advance onto next day
      date1.setDate(date1.getDate() + 1);
    }
  }

  function fillHours(date) {
    for (i = 0; i < 24; i++) {
      let cell = document.createElement("div");
      if (i < 10) {
        cell.innerText = "0" + i + ":00";
      } else {
        cell.innerText = i + ":00";
      }
      cell.style.gridRow = i + 2;
      calendar.appendChild(cell);
      cell.className = "grid-item";

      // Format time for UTC through chosen locale
      const now = new Date(date.setHours(i));
      // console.log("now", now)

      const utcNow = now.toLocaleString("en-US", {
        timeZone: searchList.value,
        timeZoneName: "long",
      });
      // console.log("utcNow", utcNow)

      let dateString = new Date(utcNow);
      // console.log("dateString", dateString)

      // Set cell id with hour-date info
      cell.dataset.date = `${dateString.toISOString()}`;
    }
  }

  // Call grid creating function with updated information
  function drawCalendar() {
    calendar.innerHTML = "";
    dateInfo();
    updateInfoDivs();
    fillDays();
    makeRows(24, difference);
  }

  // Show calculations on test box
  function updateInfoDivs() {
    beginShow.innerText = beginDateInput.value;
    endShow.innerText = endDateInput.value;
    daysShow.innerText = difference + 1;
  }

  // Get current values of inputs and calculate days
  function dateInfo() {
    date1 = new Date(beginDateInput.value);
    date2 = new Date(endDateInput.value);
    difference = (date2 - date1) / 1000 / 60 / 60 / 24;
  }

  // Make cells listen for mouseover
  function highlightCell(event) {
    let greenCells = document.querySelectorAll(".active");
    let allCells = document.querySelectorAll(".grid-item");

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
    if (event.target.classList.contains("grid-item")) {
      event.target.classList.toggle("active");
    }
  }

  // Stop cells listening for mouseover
  function resetListeners() {
    let hourInputs = document.querySelectorAll(".grid-item");
    hourInputs.forEach((element) => {
      element.removeEventListener("mouseover", toggleActive);
      element.removeEventListener("mouseover", addSlots);
      element.removeEventListener("mouseover", removeSlots);
    });
  }

  // Select active cells
  function getActiveCells() {
    let activeCells = calendar.querySelectorAll(".active");
    activeCells.forEach((cell) => {
      console.log(cell.dataset.date);
    });
  }

  // Get timezone
  function inferUserTimezone() {
    searchList.value = Intl.DateTimeFormat().resolvedOptions().timeZone;
  }

  // Get locale
  const getLang = () =>
    navigator.language ||
    navigator.browserLanguage ||
    (navigator.languages || ["en"])[0];

  // Event listeners
  searchList.addEventListener("change", drawCalendar);
  submitButton.addEventListener("click", getActiveCells);
  beginDateInput.addEventListener("change", drawCalendar);
  endDateInput.addEventListener("change", drawCalendar);
  calendar.addEventListener("mousedown", highlightCell);
  calendar.addEventListener("mousedown", toggleActive);
  calendar.addEventListener("mouseup", resetListeners);

  // Pre fill with values
  inferUserTimezone();
  drawCalendar();
};

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

// Convert these states into ranges and post to controller
