import assert from "node:assert/strict";
import test from "node:test";

import { allowedDurations } from "../../app/javascript/lib/durations.js";

test("allowedDurations keeps whole multiples of the step and rejects the rest", () => {
  assert.deepEqual(allowedDurations(60, [30, 60, 90, 120, 1440]), {
    allowed: [60, 120, 1440],
    disallowed: [30, 90],
  });
});

test("allowedDurations accepts the option values a select carries as strings", () => {
  assert.deepEqual(allowedDurations("15", ["30", "45", "1440"]), {
    allowed: ["30", "45", "1440"],
    disallowed: [],
  });
  assert.deepEqual(allowedDurations("30", ["45", "", "abc"]), {
    allowed: [],
    disallowed: ["45", "", "abc"],
  });
});

test("allowedDurations allows nothing for a missing or zero step", () => {
  assert.deepEqual(allowedDurations(0, [30, 60]), { allowed: [], disallowed: [30, 60] });
  assert.deepEqual(allowedDurations(undefined, [30]), { allowed: [], disallowed: [30] });
});
