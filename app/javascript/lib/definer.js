// The decisions of the definer on Change the times; its controller does the
// DOM work.

// Whether a cell is past, and how many guests hold it.
const definerCellState = (instant, { notBefore = null, isPast = null, counts = new Map(), key = null } = {}) => {
  const hasMillis = Boolean(instant && typeof instant.toMillis === "function");
  const past = isPast
    ? Boolean(hasMillis && isPast(instant))
    : Boolean(notBefore && hasMillis && instant.toMillis() < notBefore.toMillis());
  const iso = key || (instant && typeof instant.toUTC === "function" ? instant.toUTC().toISO() : String(instant));
  const raw = counts instanceof Map ? counts.get(iso) : counts ? counts[iso] : undefined;
  const count = Number(raw) || 0;
  return { past, count: count > 0 ? count : 0 };
};

const plural = (count, word) => `${count} ${word}${count === 1 ? "" : "s"}`;

// What the selection would take from guests: the action bar's warning and
// the form's confirm, both empty when nothing held goes.
const removalWarning = (currentOffer, selection, counts) => {
  const selected = selection instanceof Set ? selection : new Set(selection || []);
  const countOf = (iso) => {
    const raw = counts instanceof Map ? counts.get(iso) : counts ? counts[iso] : undefined;
    return Number(raw) || 0;
  };
  let removed = 0;
  let picks = 0;
  new Set(currentOffer || []).forEach((iso) => {
    const count = countOf(iso);
    if (count > 0 && !selected.has(iso)) {
      removed += 1;
      picks += count;
    }
  });
  if (removed === 0) return { removed: 0, picks: 0, warning: "", confirm: "" };
  const times = plural(removed, "time");
  const guestPicks = plural(picks, "guest pick");
  return {
    removed,
    picks,
    warning: `Removing ${times} with ${guestPicks}`,
    confirm: `Remove ${times} with ${guestPicks}?`,
  };
};

export { definerCellState, removalWarning };
