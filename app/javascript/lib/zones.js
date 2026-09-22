import { DateTime } from "luxon";

const browserTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

const isKnownZone = (name) =>
  typeof name === "string" && name !== "" && DateTime.now().setZone(name).isValid;

const availableTimeZones = (extra = []) => {
  const supported = typeof Intl.supportedValuesOf === "function" ? Intl.supportedValuesOf("timeZone") : [];
  return [...new Set([browserTimeZone, "UTC", ...extra, ...supported])].sort((left, right) => left.localeCompare(right));
};

// Fills the select and chooses `preferred` when it is a known zone, else the
// browser zone. Returns the selected zone.
const populateTimeZoneSelect = (select, preferred) => {
  const chosen = isKnownZone(preferred) ? preferred : browserTimeZone;
  select.replaceChildren();

  availableTimeZones(isKnownZone(preferred) ? [preferred] : []).forEach((timeZone) => {
    const option = document.createElement("option");
    option.value = timeZone;
    option.textContent = timeZone;
    option.selected = timeZone === chosen;
    select.appendChild(option);
  });

  return select.value || "UTC";
};

// The key every cell and selection uses for an instant: its UTC ISO time.
const slotISO = (dateTime) => dateTime.toUTC().toISO();

// ISO strings from the server, as valid instants.
const toDateTimes = (isoValues) =>
  isoValues.map((iso) => DateTime.fromISO(iso, { setZone: true })).filter((dateTime) => dateTime.isValid);

// A form's slots field: the comma-separated instants the grid serializes.
const parseSlotList = (value) => toDateTimes((value || "").split(",").filter(Boolean));

// Counts from the server keyed by ISO time, re-keyed like the cells.
const countsByInstant = (counts) =>
  new Map(
    Object.entries(counts)
      .map(([iso, count]) => [DateTime.fromISO(iso, { setZone: true }), Number(count) || 0])
      .filter(([instant]) => instant.isValid)
      .map(([instant, count]) => [slotISO(instant), count]),
  );

export { countsByInstant, parseSlotList, populateTimeZoneSelect, slotISO, toDateTimes };
