import assert from "node:assert/strict";
import test from "node:test";

import { DateTime } from "luxon";

import {
  localDayColumns,
  localDayHours,
  localHourLabels,
  localDateRangeIsAllowed,
  timeGridDimensions,
} from "../../app/javascript/lib/time_grid.js";

const TIRANE = "Europe/Tirane";
const tiraneDay = (isoDate) => DateTime.fromISO(isoDate, { zone: TIRANE });

test("a normal Europe/Tirane day contains 24 unique hourly instants", () => {
  const hours = localDayHours(tiraneDay("2026-02-10"));

  assert.equal(hours.length, 24);
  assert.equal(new Set(hours.map((hour) => hour.toUTC().toISO())).size, 24);
  assert.deepEqual(localHourLabels(hours).slice(0, 3), ["00:00", "01:00", "02:00"]);
});

test("Europe/Tirane spring transition contains 23 hours and skips 02:00", () => {
  const hours = localDayHours(tiraneDay("2026-03-29"));
  const labels = localHourLabels(hours);

  assert.equal(hours.length, 23);
  assert.equal(labels.includes("02:00"), false);
  assert.deepEqual(labels.slice(0, 4), ["00:00", "01:00", "03:00", "04:00"]);
});

test("Europe/Tirane fall transition contains both distinct 02:00 hours", () => {
  const hours = localDayHours(tiraneDay("2026-10-25"));
  const labels = localHourLabels(hours);
  const repeatedHours = labels.filter((label) => label.startsWith("02:00"));

  assert.equal(hours.length, 25);
  assert.deepEqual(repeatedHours, ["02:00 (+02:00)", "02:00 (+01:00)"]);
  assert.equal(new Set(hours.map((hour) => hour.toUTC().toISO())).size, 25);
});

test("grid dimensions use the longest real local day in a date range", () => {
  const springColumns = localDayColumns(
    tiraneDay("2026-03-28"),
    tiraneDay("2026-03-30"),
  );
  const fallColumns = localDayColumns(
    tiraneDay("2026-10-24"),
    tiraneDay("2026-10-26"),
  );

  assert.deepEqual(springColumns.map((column) => column.hours.length), [24, 23, 24]);
  assert.deepEqual(timeGridDimensions(springColumns), { columns: 3, rows: 25 });
  assert.deepEqual(fallColumns.map((column) => column.hours.length), [24, 25, 24]);
  assert.deepEqual(timeGridDimensions(fallColumns), { columns: 3, rows: 26 });
});

test("date ranges are capped at 31 inclusive local dates", () => {
  assert.equal(
    localDateRangeIsAllowed(
      tiraneDay("2026-10-01"),
      tiraneDay("2026-10-31"),
    ),
    true,
  );
  assert.equal(
    localDateRangeIsAllowed(
      tiraneDay("2026-10-01"),
      tiraneDay("2026-11-01"),
    ),
    false,
  );
});
