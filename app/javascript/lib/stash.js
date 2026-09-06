// The stashed selection re-applied after a rejected save keeps only keys the
// organizer still offers, so a reload cannot loop on cells that are gone.
const filterStash = (keys, offeredKeys) => {
  const offered = offeredKeys instanceof Set ? offeredKeys : new Set(offeredKeys || []);
  return (keys || []).filter((key) => key && offered.has(key));
};

export { filterStash };
