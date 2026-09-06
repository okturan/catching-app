// Pure helpers for the definer on the offer page. The DOM work (past cells,
// badges, the confirm attribute) lives in the component and is covered by
// the system tests; these decide, and are covered by node.

// What one definer cell is: past when the instant is before notBefore (a
// Luxon DateTime or null) or when the caller's isPast says so, and how many
// guests hold it (counts: Map or plain object keyed by the cell's UTC ISO
// key, which the caller may pass as key to save a conversion).
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

// Instants of the current offer that guests hold and that the selection no
// longer contains. removed counts those instants, picks sums the guests'
// picks on them; warning and confirm are the sentences the action bar and
// the form carry, empty when nothing held is being removed.
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
