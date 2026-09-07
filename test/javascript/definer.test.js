import assert from "node:assert/strict";
import test from "node:test";

import { DateTime } from "luxon";

import { definerCellState, removalWarning } from "../../app/javascript/lib/definer.js";

const at = (iso) => DateTime.fromISO(iso, { zone: "utc" });
const key = (iso) => at(iso).toUTC().toISO();

test("definerCellState marks a cell before the cut-off as past", () => {
  const notBefore = at("2030-01-14T10:00:00Z");

  assert.deepEqual(definerCellState(at("2030-01-14T09:00:00Z"), { notBefore }), { past: true, count: 0 });
  assert.deepEqual(definerCellState(at("2030-01-14T10:00:00Z"), { notBefore }), { past: false, count: 0 });
  assert.deepEqual(definerCellState(at("2030-01-15T10:00:00Z"), { notBefore: null }), { past: false, count: 0 });
});

test("definerCellState defers to a caller's isPast when one is given", () => {
  const notBefore = at("2030-01-14T10:00:00Z");
  const isPast = (instant) => instant.toMillis() < at("2030-01-16T00:00:00Z").toMillis();

  assert.equal(definerCellState(at("2030-01-15T10:00:00Z"), { notBefore, isPast }).past, true);
  assert.equal(definerCellState(at("2030-01-16T10:00:00Z"), { notBefore, isPast }).past, false);
  assert.equal(definerCellState(at("2030-01-15T10:00:00Z"), { isPast: () => false }).past, false);
});

test("definerCellState reports how many guests hold the cell, from a Map or a plain object", () => {
  const counts = new Map([[key("2030-01-15T10:00:00Z"), 2]]);

  assert.deepEqual(definerCellState(at("2030-01-15T10:00:00Z"), { counts }), { past: false, count: 2 });
  assert.deepEqual(definerCellState(at("2030-01-15T11:00:00Z"), { counts }), { past: false, count: 0 });
  assert.deepEqual(
    definerCellState(at("2030-01-15T10:00:00Z"), { counts: { [key("2030-01-15T10:00:00Z")]: "3" } }),
    { past: false, count: 3 },
  );
});

test("removalWarning counts the removed instants guests hold and sums their picks", () => {
  const ten = key("2030-01-15T10:00:00Z");
  const eleven = key("2030-01-15T11:00:00Z");
  const counts = new Map([[ten, 2]]);

  const removal = removalWarning([ten, eleven], new Set([eleven]), counts);
  assert.equal(removal.removed, 1);
  assert.equal(removal.picks, 2);
  assert.equal(removal.warning, "Removing 1 time with 2 guest picks");
  assert.equal(removal.confirm, "Remove 1 time with 2 guest picks?");
});

test("removalWarning reports nothing for a superset of the current offer or for removals nobody holds", () => {
  const ten = key("2030-01-15T10:00:00Z");
  const eleven = key("2030-01-15T11:00:00Z");
  const twelve = key("2030-01-15T12:00:00Z");
  const counts = new Map([[ten, 2]]);

  assert.deepEqual(removalWarning([ten, eleven], new Set([ten, eleven, twelve]), counts), {
    removed: 0,
    picks: 0,
    warning: "",
    confirm: "",
  });
  assert.equal(removalWarning([ten, eleven], new Set([ten]), counts).removed, 0, "11:00 is held by nobody");
});

test("removalWarning pluralizes and accepts an array selection", () => {
  const ten = key("2030-01-15T10:00:00Z");
  const eleven = key("2030-01-15T11:00:00Z");
  const counts = { [ten]: 1, [eleven]: 2 };

  const removal = removalWarning([ten, eleven], [], counts);
  assert.equal(removal.warning, "Removing 2 times with 3 guest picks");
  assert.equal(removalWarning([ten], [], { [ten]: 1 }).confirm, "Remove 1 time with 1 guest pick?");
});
