// Moves focus to the 422 summary so a keyboard or screen-reader visitor lands
// on what went wrong instead of at the top of a page that looks unchanged.
//
// No listener is registered: Turbo replaces the element on every render, so
// the flag lives on the element itself. A fresh render focuses again; a second
// turbo:load over the same element does not.
const initErrorSummary = () => {
  const summary = document.querySelector("#error-summary[data-autofocus]");
  if (!summary || summary.dataset.autofocused === "true") return;

  summary.dataset.autofocused = "true";
  summary.focus();
};

export { initErrorSummary };
