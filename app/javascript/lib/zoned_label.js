import { DateTime } from "luxon";

// One instant read in one zone: "20:00 (Europe/Berlin)". The server renders
// every <time data-zoned-instant> this way in the event zone; the page
// rewrites them into the picker zone with the same helper.
const zonedLabel = (iso, zone) => {
  const instant = DateTime.fromISO(String(iso || ""), { setZone: true });
  if (!instant.isValid) return "";
  const local = instant.setZone(zone);
  if (!local.isValid) return "";
  return `${local.toFormat("HH:mm")} (${local.zoneName})`;
};

export { zonedLabel };
