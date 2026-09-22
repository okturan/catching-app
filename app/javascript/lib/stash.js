// A painted selection kept for this tab across a refused save, so the paint
// comes back instead of the saved picks. Storage may be unavailable, and
// then nothing is kept.
const stashSelection = (key, selection) => {
  try {
    window.sessionStorage.setItem(key, [...selection].join(","));
  } catch (_error) {
    // Nothing kept.
  }
};

// The stashed selection, taken once.
const takeStash = (key, offeredKeys) => {
  try {
    const stashed = window.sessionStorage.getItem(key);
    window.sessionStorage.removeItem(key);
    return stashed ? filterStash(stashed.split(","), offeredKeys) : [];
  } catch (_error) {
    return [];
  }
};

// Only cells the organizer still offers come back, so a save refused for a
// removed time cannot be repeated by the re-apply.
const filterStash = (keys, offeredKeys) => {
  const offered = offeredKeys instanceof Set ? offeredKeys : new Set(offeredKeys || []);
  return (keys || []).filter((key) => key && offered.has(key));
};

export { filterStash, stashSelection, takeStash };
