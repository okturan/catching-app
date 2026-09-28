import { DateTime } from "luxon";

const MAX_DATE_RANGE_DAYS = 31;
const MINUTES_PER_DAY = 1440;

const isValid = (value) => DateTime.isDateTime(value) && value.isValid;

const localDateRangeIsAllowed = (
  firstDay,
  lastDay,
  maximumDays = MAX_DATE_RANGE_DAYS,
) => {
  if (!isValid(firstDay) || !isValid(lastDay)) return false;

  const rangeStart = firstDay.startOf("day");
  const rangeEnd = lastDay.setZone(rangeStart.zoneName).startOf("day");
  const elapsedCalendarDays = rangeEnd.diff(rangeStart, "days").days;

  return elapsedCalendarDays >= 0 && elapsedCalendarDays < maximumDays;
};

// Every instant of one local day, stepping by exact duration from local
// midnight to the next local midnight. Days whose midnight does not exist
// (spring-forward at 00:00) start at the first valid instant and end at the
// real start of the next day, so no instant is duplicated or dropped.
const localDaySlots = (dateTime, slotMinutes = 60) => {
  if (!isValid(dateTime)) return [];

  const startOfDay = dateTime.startOf("day");
  const startOfNextDay = startOfDay.plus({ days: 1 }).startOf("day");
  const slots = [];

  for (
    let slot = startOfDay;
    slot.toMillis() < startOfNextDay.toMillis();
    slot = slot.plus({ minutes: slotMinutes })
  ) {
    slots.push(slot);
  }

  return slots;
};

const localDayHours = (dateTime) => localDaySlots(dateTime, 60);

const localDayColumns = (firstDay, lastDay, slotMinutes = 60) => {
  if (!isValid(firstDay) || !isValid(lastDay)) return [];

  const rangeStart = firstDay.startOf("day");
  const rangeEnd = lastDay.setZone(rangeStart.zoneName).startOf("day");
  if (rangeEnd.toMillis() < rangeStart.toMillis()) return [];

  const columns = [];
  for (
    let day = rangeStart;
    day.toMillis() <= rangeEnd.toMillis();
    day = day.plus({ days: 1 }).startOf("day")
  ) {
    const slots = localDaySlots(day, slotMinutes);
    columns.push({ day, slots, hours: slots });
  }

  return columns;
};

const localSlotLabels = (slots) => {
  const wallClockCounts = slots.reduce((counts, slot) => {
    const wallClock = slot.toFormat("HH:mm");
    counts.set(wallClock, (counts.get(wallClock) || 0) + 1);
    return counts;
  }, new Map());

  return slots.map((slot) => {
    const wallClock = slot.toFormat("HH:mm");
    return wallClockCounts.get(wallClock) > 1
      ? `${wallClock} (${slot.toFormat("ZZ")})`
      : wallClock;
  });
};

const localHourLabels = localSlotLabels;

const timeGridDimensions = (columns) => {
  const maximumSlots = columns.reduce(
    (maximum, column) =>
      Math.max(maximum, (column.slots || column.hours || []).length),
    0,
  );

  return {
    columns: columns.length,
    rows: maximumSlots === 0 ? 0 : maximumSlots + 1,
  };
};

const slotKey = (dateTime) => dateTime.toUTC().toISO();
const wallMinutesOf = (dateTime) => dateTime.hour * 60 + dateTime.minute;
const wallLabel = (wallMinutes) =>
  `${String(Math.floor(wallMinutes / 60)).padStart(2, "0")}:${String(
    wallMinutes % 60,
  ).padStart(2, "0")}`;

// Builds the show grid from the organizer's offered instants.
//
// Cells are the organizer's lattice instants (so a +05:30 organizer viewed
// from UTC still matches by identity), keyed by viewer-local date and by a
// row key (wall-clock minutes, DST occurrence). Rows are limited to one
// circular band: offered wall clocks are sorted modulo a day, the largest
// gap between them is found (wrapping past midnight), and the band starts
// just after that gap, so an offer that crosses the viewer's midnight stays
// compact instead of expanding to the full day.
const offeredGrid = (
  offeredInstants,
  { eventZone = null, viewerZone = "UTC", slotMinutes = 60 } = {},
) => {
  const offered = (offeredInstants || []).filter(isValid);
  const empty = {
    columns: [],
    rows: [],
    cells: new Map(),
    offeredCount: 0,
    bandStart: null,
    bandEnd: null,
  };
  if (offered.length === 0) return empty;

  const offeredKeys = new Set(offered.map(slotKey));
  const sorted = [...offered].sort((a, b) => a.toMillis() - b.toMillis());
  const first = sorted[0];
  const last = sorted[sorted.length - 1];

  let lattice;
  if (eventZone) {
    lattice = localDayColumns(
      first.setZone(eventZone),
      last.setZone(eventZone),
      slotMinutes,
    ).flatMap((column) => column.slots);
  } else {
    lattice = [];
    for (
      let instant = first;
      instant.toMillis() <= last.toMillis();
      instant = instant.plus({ minutes: slotMinutes })
    ) {
      lattice.push(instant);
    }
  }

  const occurrences = new Map();
  const entries = lattice.map((instant) => {
    const local = instant.setZone(viewerZone);
    const dateKey = local.toISODate();
    const wall = wallMinutesOf(local);
    const occurrenceKey = `${dateKey}|${wall}`;
    const occurrence = occurrences.get(occurrenceKey) || 0;
    occurrences.set(occurrenceKey, occurrence + 1);
    const iso = slotKey(local);

    return {
      instant: local,
      iso,
      dateKey,
      wall,
      occurrence,
      offered: offeredKeys.has(iso),
      offset: local.toFormat("ZZ"),
    };
  });

  const offeredWalls = [
    ...new Set(entries.filter((entry) => entry.offered).map((e) => e.wall)),
  ].sort((a, b) => a - b);
  if (offeredWalls.length === 0) return empty;

  let bandStart = offeredWalls[0];
  let bandEnd = offeredWalls[offeredWalls.length - 1];
  if (offeredWalls.length > 1) {
    let largestGap = -1;
    let gapIndex = 0;
    offeredWalls.forEach((wall, index) => {
      const next = offeredWalls[(index + 1) % offeredWalls.length];
      const gap = (next - wall + MINUTES_PER_DAY) % MINUTES_PER_DAY;
      if (gap > largestGap) {
        largestGap = gap;
        gapIndex = index;
      }
    });
    bandEnd = offeredWalls[gapIndex];
    bandStart = offeredWalls[(gapIndex + 1) % offeredWalls.length];
  }

  const rotate = (wall) => (wall - bandStart + MINUTES_PER_DAY) % MINUTES_PER_DAY;
  const bandLength = rotate(bandEnd);
  const inBand = entries.filter((entry) => rotate(entry.wall) <= bandLength);

  const rowMap = new Map();
  inBand.forEach((entry) => {
    const key = `${entry.wall}|${entry.occurrence}`;
    if (!rowMap.has(key)) {
      rowMap.set(key, {
        key,
        wall: entry.wall,
        occurrence: entry.occurrence,
        label:
          entry.occurrence > 0
            ? `${wallLabel(entry.wall)} (${entry.offset})`
            : wallLabel(entry.wall),
      });
    }
  });
  const rows = [...rowMap.values()].sort(
    (a, b) => rotate(a.wall) - rotate(b.wall) || a.occurrence - b.occurrence,
  );
  rows.forEach((row, index) => {
    row.crossesMidnight = index > 0 && row.wall < rows[index - 1].wall;
  });

  const columnMap = new Map();
  inBand.forEach((entry) => {
    if (!columnMap.has(entry.dateKey)) {
      columnMap.set(entry.dateKey, {
        key: entry.dateKey,
        day: entry.instant.startOf("day"),
      });
    }
  });
  const columns = [...columnMap.values()].sort((a, b) =>
    a.key.localeCompare(b.key),
  );

  const cells = new Map();
  inBand.forEach((entry) => {
    cells.set(`${entry.dateKey}|${entry.wall}|${entry.occurrence}`, entry);
  });

  return {
    columns,
    rows,
    cells,
    offeredCount: offeredKeys.size,
    bandStart,
    bandEnd,
  };
};

const cellKey = (column, row) => `${column.key}|${row.wall}|${row.occurrence}`;

export {
  MAX_DATE_RANGE_DAYS,
  cellKey,
  localDayColumns,
  localDayHours,
  localDaySlots,
  localHourLabels,
  localSlotLabels,
  localDateRangeIsAllowed,
  offeredGrid,
  timeGridDimensions,
};
