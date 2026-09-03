import assert from "node:assert/strict";
import test from "node:test";

import { DateTime } from "luxon";

import {
  localDayColumns,
  localDayHours,
  localDaySlots,
  localHourLabels,
  localSlotLabels,
  localDateRangeIsAllowed,
  offeredGrid,
  timeGridDimensions,
} from "../../app/javascript/lib/time_grid.js";

const TIRANE = "Europe/Tirane";
const tiraneDay = (isoDate) => DateTime.fromISO(isoDate, { zone: TIRANE });
const dayIn = (zone) => (isoDate) => DateTime.fromISO(isoDate, { zone });
const utcKeys = (instants) => instants.map((instant) => instant.toUTC().toISO());

test("a normal Europe/Tirane day contains 24 unique hourly instants", () => {
  const hours = localDayHours(tiraneDay("2026-02-10"));

  assert.equal(hours.length, 24);
  assert.equal(new Set(utcKeys(hours)).size, 24);
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
  assert.equal(new Set(utcKeys(hours)).size, 25);
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
    localDateRangeIsAllowed(tiraneDay("2026-10-01"), tiraneDay("2026-10-31")),
    true,
  );
  assert.equal(
    localDateRangeIsAllowed(tiraneDay("2026-10-01"), tiraneDay("2026-11-01")),
    false,
  );
});

test("Tirane days step correctly at 15, 30 and 60 minutes", () => {
  const counts = (isoDate) =>
    [15, 30, 60].map((step) => localDaySlots(tiraneDay(isoDate), step).length);

  assert.deepEqual(counts("2026-03-29"), [92, 46, 23]);
  assert.deepEqual(counts("2026-02-10"), [96, 48, 24]);
  assert.deepEqual(counts("2026-10-25"), [100, 50, 25]);
  assert.equal(
    new Set(utcKeys(localDaySlots(tiraneDay("2026-10-25"), 15))).size,
    100,
  );
});

test("a zone whose midnight vanishes neither duplicates nor drops a day", () => {
  const santiago = dayIn("America/Santiago");
  const columns = localDayColumns(santiago("2026-09-05"), santiago("2026-09-08"));
  const all = columns.flatMap((column) => column.slots);

  assert.deepEqual(columns.map((column) => column.slots.length), [24, 23, 24, 24]);
  assert.equal(new Set(utcKeys(all)).size, all.length);
  assert.equal(columns[3].day.toISODate(), "2026-09-08");

  const cairo = dayIn("Africa/Cairo");
  assert.equal(
    localDayColumns(cairo("2026-04-23"), cairo("2026-04-25")).length,
    3,
  );
});

test("Lord Howe's half-hour shift labels the repeated cells with their offset", () => {
  const lordHowe = dayIn("Australia/Lord_Howe");
  const slots = localDaySlots(lordHowe("2026-04-05"), 60);
  const labels = localSlotLabels(slots);

  assert.equal(slots.length, 25);
  assert.equal(new Set(utcKeys(slots)).size, 25);
  assert.deepEqual(labels.slice(0, 4), ["00:00", "01:00", "01:30", "02:30"]);
  assert.equal(labels.filter((label) => label.includes("(")).length, 0);
});

test("offeredGrid matches a half-hour organizer by identity from UTC", () => {
  const kolkata = dayIn("Asia/Kolkata");
  const offered = localDaySlots(kolkata("2026-02-10"), 60);
  const grid = offeredGrid(offered, {
    eventZone: "Asia/Kolkata",
    viewerZone: "UTC",
    slotMinutes: 60,
  });

  assert.equal(grid.rows.length, 24);
  assert.equal(grid.columns.length, 2);
  const offeredCells = [...grid.cells.values()].filter((cell) => cell.offered);
  assert.equal(offeredCells.length, 24);
  assert.ok(offeredCells.every((cell) => cell.iso.endsWith(":30:00.000Z")));
});

test("offeredGrid keeps a cross-midnight offer compact on a circular band", () => {
  const berlin = dayIn("Europe/Berlin");
  const day = berlin("2026-09-15");
  const offered = [];
  for (let minutes = 9 * 60; minutes <= 18 * 60; minutes += 30) {
    offered.push(day.plus({ minutes }));
  }

  const auckland = offeredGrid(offered, {
    eventZone: "Europe/Berlin",
    viewerZone: "Pacific/Auckland",
    slotMinutes: 30,
  });
  assert.equal(auckland.rows.length, 19);
  assert.equal(auckland.rows[0].label, "19:00");
  assert.equal(auckland.rows.filter((row) => row.crossesMidnight).length, 1);

  const tokyo = offeredGrid(offered, {
    eventZone: "Europe/Berlin",
    viewerZone: "Asia/Tokyo",
    slotMinutes: 30,
  });
  assert.equal(tokyo.rows.length, 19);
  assert.equal(tokyo.rows[0].label, "16:00");

  const losAngeles = offeredGrid(offered, {
    eventZone: "Europe/Berlin",
    viewerZone: "America/Los_Angeles",
    slotMinutes: 30,
  });
  assert.equal(losAngeles.rows.length, 19);
  assert.equal(losAngeles.rows.filter((row) => row.crossesMidnight).length, 0);
});

test("offeredGrid aligns equal wall clocks across days and fills placeholders", () => {
  const berlin = dayIn("Europe/Berlin");
  const monday = berlin("2026-09-14");
  const tuesday = berlin("2026-09-15");
  const offered = [
    ...[9, 10, 11].map((hour) => monday.plus({ hours: hour })),
    ...[14, 15, 16, 17].map((hour) => tuesday.plus({ hours: hour })),
  ];
  const grid = offeredGrid(offered, {
    eventZone: "Europe/Berlin",
    viewerZone: "Europe/Berlin",
    slotMinutes: 60,
  });

  assert.equal(grid.columns.length, 2);
  assert.deepEqual(
    grid.rows.map((row) => row.label),
    ["09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00", "17:00"],
  );
  const mondayAfternoon = grid.cells.get(`2026-09-14|${14 * 60}|0`);
  assert.equal(mondayAfternoon.offered, false);
});

test("offeredGrid adds one occurrence row on a fall-back day", () => {
  const offered = localDaySlots(tiraneDay("2026-10-25"), 60);
  const grid = offeredGrid(offered, {
    eventZone: TIRANE,
    viewerZone: TIRANE,
    slotMinutes: 60,
  });

  assert.equal(grid.rows.length, 25);
  assert.equal(grid.rows.filter((row) => row.occurrence === 1).length, 1);
});

test("offeredGrid without an event zone infers the lattice from the offer", () => {
  const kolkata = dayIn("Asia/Kolkata");
  const offered = [10, 11, 13].map((hour) => kolkata("2026-02-10").plus({ hours: hour }));
  const grid = offeredGrid(offered, { viewerZone: "UTC", slotMinutes: 60 });

  assert.equal(grid.rows.length, 4);
  assert.equal([...grid.cells.values()].filter((cell) => !cell.offered).length, 1);
});
