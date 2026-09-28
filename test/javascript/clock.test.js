import assert from "node:assert/strict";
import test from "node:test";

import { DateTime } from "luxon";

import { offsetLabel, shiftLabel } from "../../app/javascript/lib/clock.js";

test("shiftLabel says how far the ruler moved the shared moment", () => {
  assert.equal(shiftLabel(0), "now");
  assert.equal(shiftLabel(180), "+3h");
  assert.equal(shiftLabel(-90), "−1h 30m");
});

test("offsetLabel names a zone's offset, half hours included", () => {
  const at = (zone) => DateTime.fromISO("2030-01-10T12:00:00Z").setZone(zone);
  assert.equal(offsetLabel(at("Asia/Kolkata")), "UTC+5:30");
  assert.equal(offsetLabel(at("America/New_York")), "UTC−5");
  assert.equal(offsetLabel(at("UTC")), "UTC+0");
});
