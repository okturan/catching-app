import { DateTime } from "luxon";

// The two shapes a zoned instant takes, matching EventsHelper::ZONED_FORMATS:
// a clock reading, or a full date with the clock (data-zoned-format="date-time").
const FORMATS = {
  time: "HH:mm",
  "date-time": "ccc d LLL yyyy HH:mm",
};

// One instant read in one zone: "20:00 (Europe/Berlin)". The server renders
// every <time data-zoned-instant> this way in the event zone; the page
// rewrites them into the picker zone with the same helper, passing the
// element's data-zoned-format so a dated label keeps its date.
const zonedLabel = (iso, zone, { format = "time" } = {}) => {
  const instant = DateTime.fromISO(String(iso || ""), { setZone: true });
  if (!instant.isValid) return "";
  const local = instant.setZone(zone);
  if (!local.isValid) return "";
  return `${local.toFormat(FORMATS[format] || FORMATS.time)} (${local.zoneName})`;
};

export { zonedLabel };
