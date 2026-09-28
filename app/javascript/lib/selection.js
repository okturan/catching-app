import { DateTime } from "luxon";

const strokeMode = (cellSelected) => (cellSelected ? "remove" : "add");

const applyStroke = (selection, iso, mode) => {
  if (mode === "add") {
    selection.add(iso);
  } else {
    selection.delete(iso);
  }
  return selection;
};

const toISO = (dateTime) => dateTime.toUTC().toISO();
const parseISO = (iso) => DateTime.fromISO(iso, { setZone: true });

// Moves every selected instant so that it keeps its wall clock in the new
// zone: 09:00 Europe/Berlin becomes 09:00 Asia/Kolkata.
const remapZone = (selection, fromZone, toZone) =>
  new Set(
    [...selection].map((iso) =>
      toISO(
        parseISO(iso).setZone(fromZone).setZone(toZone, { keepLocalTime: true }),
      ),
    ),
  );

// Refining expands each slot into its sub-cells; coarsening snaps each slot
// to the coarser grid anchored at local midnight in the given zone.
const rescale = (selection, fromMinutes, toMinutes, zone) => {
  const rescaled = new Set();

  for (const iso of selection) {
    const instant = parseISO(iso).setZone(zone);

    if (toMinutes < fromMinutes) {
      for (let offset = 0; offset < fromMinutes; offset += toMinutes) {
        rescaled.add(toISO(instant.plus({ minutes: offset })));
      }
    } else {
      const startOfDay = instant.startOf("day");
      const minutes = instant.diff(startOfDay, "minutes").minutes;
      const snapped = Math.floor(minutes / toMinutes) * toMinutes;
      rescaled.add(toISO(startOfDay.plus({ minutes: snapped })));
    }
  }

  return rescaled;
};

const formatDuration = (minutes) => {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${rest} min`;
  if (rest === 0) return `${hours} h`;
  return `${hours} h ${rest} min`;
};

// The action bar sentence. For the organizer a planned length
// (durationMinutes, from data-duration-minutes) is compared with the
// selected window: a warning, never a refusal, so the sentence only grows.
const summary = (
  selection,
  { role = "guest", zone = "UTC", slotMinutes = 60, durationMinutes = null } = {},
) => {
  const instants = [...selection]
    .map((iso) => parseISO(iso).setZone(zone))
    .filter((instant) => instant.isValid)
    .sort((a, b) => a.toMillis() - b.toMillis());

  if (instants.length === 0) return "No times selected";

  if (role === "organizer") {
    const contiguous = instants.every(
      (instant, index) =>
        index === 0 ||
        instant.diff(instants[index - 1], "minutes").minutes === slotMinutes,
    );
    if (!contiguous) return "Not one continuous window";

    const start = instants[0];
    const end = instants[instants.length - 1].plus({ minutes: slotMinutes });
    const selected = instants.length * slotMinutes;
    let text = `${start.toFormat("ccc d LLL HH:mm")}–${end.toFormat("HH:mm")} (${formatDuration(
      selected,
    )})`;
    const planned = Number(durationMinutes);
    if (planned > 0) {
      text += ` · planned ${formatDuration(planned)}`;
      if (selected < planned) text += ", shorter than planned";
    }
    return text;
  }

  const days = new Set(instants.map((instant) => instant.toISODate())).size;
  return `${instants.length} slot${instants.length === 1 ? "" : "s"} on ${days} day${
    days === 1 ? "" : "s"
  }`;
};

export { applyStroke, remapZone, rescale, strokeMode, summary };
