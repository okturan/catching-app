import assert from "node:assert/strict";
import test from "node:test";

import { filterStash } from "../../app/javascript/lib/stash.js";

test("filterStash keeps only the keys that are still offered", () => {
  assert.deepEqual(filterStash(["<10:00>", "<11:00>"], ["<10:00>"]), ["<10:00>"]);
  assert.deepEqual(filterStash(["<10:00>", "<11:00>"], new Set(["<11:00>", "<12:00>"])), ["<11:00>"]);
});

test("filterStash drops blanks and survives missing input", () => {
  assert.deepEqual(filterStash(["", "<10:00>", undefined], ["<10:00>"]), ["<10:00>"]);
  assert.deepEqual(filterStash([], ["<10:00>"]), []);
  assert.deepEqual(filterStash(null, ["<10:00>"]), []);
  assert.deepEqual(filterStash(["<10:00>"], null), []);
});
