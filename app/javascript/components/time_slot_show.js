import moment from "moment-timezone";

const initTimeSlotShow = () => {
  if (!document.querySelector("#time-grid-show")) {
    return;
  }

  const receivedTimeSlots = document.querySelector("#received-time-slots");
  const guestTimeSlots = document.querySelector("#guest-time-slots");
  const timeGrid = document.querySelector("#time-grid-show");
  const tzpicker = document.querySelector("#timezone-picker-show");
  const disableCheckbox = document.querySelector("#hide-disabled-cells");

  let receivedSlotsArray;
  let guestSlotsArray;
  let receivedDate1;
  let receivedDate2;
  let date1;
  let date2;
  let difference;

  function drawTimeGrid() {
    timeGrid.innerHTML = "";
    receivedSlotsArray = isoToMoment();
    initialDatesGetSet();
    fillDays();
    makeRows(25, difference + 1);
    updateCells();
    if (guestTimeSlots.value != "[]" ) {
      guestSlotsArray = isoToMomentGuest();
      updateGuestCells();
    }
    disableCheckbox.checked = false
  }

  function initialDatesGetSet() {
    receivedDate1 = moment.min(receivedSlotsArray);
    date1 = moment(receivedDate1).startOf("day");
    receivedDate2 = moment.max(receivedSlotsArray);
    date2 = moment(receivedDate2).startOf("day");
    difference = date2.diff(date1, "days");
  }
  
  function fillDays() {
    for (let c = 0; c <= difference; c++) {
      let cell = document.createElement("div");
      cell.innerText = moment(date1).format("MMM Do ddd zz");
      timeGrid.appendChild(cell).className = "grid-item header";
      cell.style.gridColumn = c + 1
      // Fill hour info for each day
      fillHours(date1, c);
      // Advance onto next day
      date1 = date1.add(1, "day");
    }
  }
  
  function fillHours(date, c) {
    for (let i = 0; i < 24; i++) {
      // Create grid cells
      let cell = document.createElement("div");
      cell.innerText = date.format("HH:mm");
      cell.style.gridColumn = c + 1
      timeGrid.appendChild(cell);
      cell.className = "grid-item hour";
      cell.dataset.date = date.toISOString();
      // Increment hour
      date = moment(date).add(1, "hour");
    }
  }

  function updateGuestCells() {
    guestSlotsArray.forEach((receivedSlot) => {
      let receivedSlotISO = receivedSlot.toISOString();
      let query = `[data-date="` + receivedSlotISO + `"]`;
      let targetCell = timeGrid.querySelector(query);

      if (targetCell != null) {
        targetCell.insertAdjacentHTML("afterbegin", '🙋');
      }
    });
  }
  
  function updateCells() {
    receivedSlotsArray.forEach((receivedSlot) => {
      let receivedSlotISO = receivedSlot.toISOString();
      let query = `[data-date="` + receivedSlotISO + `"]`;
      let targetCell = timeGrid.querySelector(query);

      if (targetCell != null) {
        targetCell.classList.toggle("received");
      }
    });

    let inactiveCells = timeGrid.querySelectorAll(":not(.received).hour");
    inactiveCells.forEach((inactiveCell) => {
      inactiveCell.classList.toggle("inactive");
    });
  }

  // Make cells listen for mouseover
  function highlightCell(event) {
    let receivedCells = document.querySelectorAll(".received");
    let allCells = document.querySelectorAll(":not(.inactive).hour");

    if (event.target.classList.contains("active")) {
      receivedCells.forEach((element) => {
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
    if (!event.target.classList.contains("inactive")) {
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

  function getActiveCells() {
    let slots = [];
    let activeCells = timeGrid.querySelectorAll(".active");
    activeCells.forEach((cell) => {
      slots.push(cell.dataset.date);
    });
    document.querySelector("#new-time-slot-array").value = slots;
  }

  function getActiveCellsFinalize() {
    let slots = [];
    let activeCells = timeGrid.querySelectorAll(".active");
    activeCells.forEach((cell) => {
      slots.push(cell.dataset.date);
    });
    document.querySelector("#final-time-slot-array").value = slots;
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

  function changeTimezone() {
    moment.tz.setDefault(tzpicker.value);
    drawTimeGrid();
  }

  function isoToMoment() {
    const iso_regex =
      /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([zZ]|([\+-])([01]\d|2[0-3]):?([0-5]\d)?)*/g;
    let array = receivedTimeSlots.value.match(iso_regex);
    return array.map((slot) => moment(slot));
  }

  function isoToMomentGuest() {
    const iso_regex =
      /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([zZ]|([\+-])([01]\d|2[0-3]):?([0-5]\d)?)*/g;
    let array = guestTimeSlots.value.match(iso_regex);
    return array.map((slot) => moment(slot));
  }

  function getLang() {
    navigator.language ||
      navigator.browserLanguage ||
      (navigator.languages || ["en"])[0];
  }

  function makeRows(rows, cols) {
    timeGrid.style.setProperty("--grid-rows", rows);
    timeGrid.style.setProperty("--grid-cols", cols);
  }

  function hideDisabled(event) {
    let inactiveCells = document.querySelectorAll(":not(.received).hour");

    if (event.target.checked == false) {
      inactiveCells.forEach((inactiveCell) => {
      inactiveCell.classList.toggle("disabled");
      });
    } else if (event.target.checked == true) {
      inactiveCells.forEach((inactiveCell) => {
      inactiveCell.classList.toggle("disabled");
      })
    };
  }

// <input id="guest-list"

  if (document.querySelector("#is-host").value == "no") {
    timeGrid.addEventListener("mousedown", highlightCell);
    timeGrid.addEventListener("mousedown", toggleActive);
    timeGrid.addEventListener("mouseup", resetListeners);
    tzpicker.addEventListener("change", changeTimezone);
  } else {
    timeGrid.addEventListener("mousedown", toggleActive);
    timeGrid.addEventListener("mouseup", getActiveCellsFinalize);
  }

  disableCheckbox.addEventListener("change", hideDisabled);


  populateTimezones();
  moment.tz.setDefault(tzpicker.value);
  drawTimeGrid();
};

export { initTimeSlotShow };
