import assert from "node:assert/strict";
import test from "node:test";

import { DateTime } from "luxon";

import {
  applyStroke,
  remapZone,
  rescale,
  strokeMode,
  summary,
} from "../../app/javascript/lib/paint.js";

const iso = (value, zone) => DateTime.fromISO(value, { zone }).toUTC().toISO();

test("strokeMode removes from a selected cell and adds to an empty one", () => {
  assert.equal(strokeMode(true), "remove");
  assert.equal(strokeMode(false), "add");
});

test("applyStroke mutates the selection set", () => {
  const selection = new Set();
  applyStroke(selection, "a", "add");
  applyStroke(selection, "b", "add");
  applyStroke(selection, "a", "remove");
  assert.deepEqual([...selection], ["b"]);
});

test("remapZone keeps the wall clock in the new zone", () => {
  const selection = new Set([iso("2026-02-10T09:00", "Europe/Berlin")]);
  const remapped = remapZone(selection, "Europe/Berlin", "Asia/Kolkata");

  assert.deepEqual([...remapped], [iso("2026-02-10T09:00", "Asia/Kolkata")]);
});

test("rescale refines into sub-cells and coarsens by snapping to local midnight", () => {
  const zone = "Europe/Berlin";
  const refined = rescale(new Set([iso("2026-02-10T10:00", zone)]), 60, 30, zone);
  assert.deepEqual(
    [...refined].sort(),
    [iso("2026-02-10T10:00", zone), iso("2026-02-10T10:30", zone)].sort(),
  );

  const coarsened = rescale(new Set([iso("2026-02-10T10:30", zone)]), 30, 60, zone);
  assert.deepEqual([...coarsened], [iso("2026-02-10T10:00", zone)]);
});

test("summary counts slots and days for guests", () => {
  const zone = "Europe/Berlin";
  const selection = new Set([
    iso("2026-02-10T10:00", zone),
    iso("2026-02-10T11:00", zone),
    iso("2026-02-11T10:00", zone),
  ]);

  assert.equal(summary(selection, { role: "guest", zone }), "3 slots on 2 days");
  assert.equal(summary(new Set(), { role: "guest", zone }), "No times selected");
});

test("summary reports the window or a broken run for organizers", () => {
  const zone = "Europe/Berlin";
  const contiguous = new Set([
    iso("2026-02-10T10:00", zone),
    iso("2026-02-10T10:30", zone),
  ]);
  const broken = new Set([
    iso("2026-02-10T10:00", zone),
    iso("2026-02-10T12:00", zone),
  ]);

  assert.equal(
    summary(contiguous, { role: "organizer", zone, slotMinutes: 30 }),
    "Tue 10 Feb 10:00–11:00 (1 h)",
  );
  assert.equal(
    summary(broken, { role: "organizer", zone, slotMinutes: 30 }),
    "Not one continuous window",
  );
});
