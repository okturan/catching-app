import { DateTime } from "luxon";

const browserTimeZone =
  Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

const isKnownZone = (name) =>
  typeof name === "string" && name !== "" && DateTime.now().setZone(name).isValid;

const availableTimeZones = (extra = []) => {
  const supported =
    typeof Intl.supportedValuesOf === "function"
      ? Intl.supportedValuesOf("timeZone")
      : [];

  return [...new Set([browserTimeZone, "UTC", ...extra, ...supported])].sort(
    (left, right) => left.localeCompare(right),
  );
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

const parseSerializedDateTimes = (value) => {
  let isoValues;

  try {
    const parsed = JSON.parse(value);
    isoValues = Array.isArray(parsed) ? parsed : [];
  } catch (_error) {
    isoValues =
      (value || "").match(
        /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/g,
      ) || [];
  }

  return isoValues
    .map((isoValue) => DateTime.fromISO(isoValue, { setZone: true }))
    .filter((dateTime) => dateTime.isValid);
};

const parseSerializedCounts = (value) => {
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (_error) {
    return {};
  }
};

const slotISO = (dateTime) => dateTime.toUTC().toISO();

export {
  browserTimeZone,
  isKnownZone,
  parseSerializedCounts,
  parseSerializedDateTimes,
  populateTimeZoneSelect,
  slotISO,
};
