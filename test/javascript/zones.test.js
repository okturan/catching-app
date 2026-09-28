import assert from "node:assert/strict";
import test from "node:test";

import { DateTime } from "luxon";

import { currentZoneName } from "../../app/javascript/lib/zones.js";

test("currentZoneName gives a renamed zone its current IANA name", () => {
  assert.equal(currentZoneName("Asia/Calcutta"), "Asia/Kolkata");
  assert.equal(currentZoneName("Europe/Kiev"), "Europe/Kyiv");
  assert.equal(currentZoneName("America/Buenos_Aires"), "America/Argentina/Buenos_Aires");
});

test("currentZoneName leaves every other zone as it is", () => {
  assert.equal(currentZoneName("Europe/Berlin"), "Europe/Berlin");
  assert.equal(currentZoneName("Asia/Kolkata"), "Asia/Kolkata");
  assert.equal(currentZoneName("UTC"), "UTC");
});

test("every current name is a zone Luxon can use", () => {
  ["Asia/Kolkata", "Europe/Kyiv", "Asia/Ho_Chi_Minh", "America/Nuuk", "Pacific/Kanton", "America/Indiana/Indianapolis"].forEach((zone) => {
    assert.ok(DateTime.now().setZone(zone).isValid, zone);
  });
});
