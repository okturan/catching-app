import { DateTime } from "luxon";

const browserTimeZone =
  Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

const availableTimeZones = () => {
  const supported =
    typeof Intl.supportedValuesOf === "function"
      ? Intl.supportedValuesOf("timeZone")
      : [];

  return [...new Set([browserTimeZone, "UTC", ...supported])].sort((left, right) =>
    left.localeCompare(right),
  );
};

const populateTimeZoneSelect = (select) => {
  select.replaceChildren();

  availableTimeZones().forEach((timeZone) => {
    const option = document.createElement("option");
    option.value = timeZone;
    option.textContent = timeZone;
    option.selected = timeZone === browserTimeZone;
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
      value.match(
        /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/g,
      ) || [];
  }

  return isoValues
    .map((isoValue) => DateTime.fromISO(isoValue, { setZone: true }))
    .filter((dateTime) => dateTime.isValid);
};

const slotISO = (dateTime) => dateTime.toUTC().toISO();

export {
  browserTimeZone,
  parseSerializedDateTimes,
  populateTimeZoneSelect,
  slotISO,
};
