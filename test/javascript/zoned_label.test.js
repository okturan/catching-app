import assert from "node:assert/strict";
import test from "node:test";

import { zonedLabel } from "../../app/javascript/lib/zoned_label.js";

test("zonedLabel reads one instant in two zones", () => {
  assert.equal(zonedLabel("2030-01-15T19:00:00Z", "Europe/Berlin"), "20:00 (Europe/Berlin)");
  assert.equal(zonedLabel("2030-01-15T19:00:00Z", "Asia/Kolkata"), "00:30 (Asia/Kolkata)");
  assert.equal(zonedLabel("2030-07-15T19:00:00Z", "Europe/Berlin"), "21:00 (Europe/Berlin)");
});

test("zonedLabel keeps an offset instant and names the zone it was asked for", () => {
  assert.equal(zonedLabel("2030-01-15T20:00:00+01:00", "UTC"), "19:00 (UTC)");
  assert.equal(zonedLabel("2030-01-15T20:00:00+01:00", "America/New_York"), "14:00 (America/New_York)");
});

test("zonedLabel is empty for an unreadable instant or zone", () => {
  assert.equal(zonedLabel("not a date", "Europe/Berlin"), "");
  assert.equal(zonedLabel("", "Europe/Berlin"), "");
  assert.equal(zonedLabel(undefined, "Europe/Berlin"), "");
  assert.equal(zonedLabel("2030-01-15T19:00:00Z", "Mars/Olympus"), "");
});

test("zonedLabel keeps the date for a date-time element and falls back to the clock", () => {
  assert.equal(
    zonedLabel("2030-01-15T19:00:00Z", "Europe/Berlin", { format: "date-time" }),
    "Tue 15 Jan 2030 20:00 (Europe/Berlin)",
  );
  assert.equal(
    zonedLabel("2030-01-15T22:00:00Z", "Asia/Kolkata", { format: "date-time" }),
    "Wed 16 Jan 2030 03:30 (Asia/Kolkata)",
  );
  assert.equal(zonedLabel("2030-01-15T19:00:00Z", "Europe/Berlin", { format: "unknown" }), "20:00 (Europe/Berlin)");
});
