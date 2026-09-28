import { Controller } from "@hotwired/stimulus";

import { allowedDurations } from "../lib/durations";

// The planned-length select of the planning form. Lengths that are not a
// whole number of the step's slots are disabled; a chosen length that stops
// fitting falls back to "Not set", and the note says which one went.
export default class extends Controller {
  static targets = ["select", "note"];
  static values = { step: Number };

  connect() {
    this.disableUnfitting();
  }

  restep({ detail: { slotMinutes } }) {
    this.stepValue = slotMinutes;
    const cleared = this.disableUnfitting();
    this.noteTarget.textContent = cleared
      ? `Planned length cleared: ${cleared} is not a whole number of ${slotMinutes}-minute slots.`
      : "";
  }

  // Returns the label of a chosen length it had to clear.
  disableUnfitting() {
    const options = [...this.selectTarget.options].filter((option) => option.value !== "");
    const fits = new Set(allowedDurations(this.stepValue, options.map((option) => option.value)).allowed);
    options.forEach((option) => {
      option.disabled = !fits.has(option.value);
    });

    const chosen = this.selectTarget.selectedOptions[0];
    if (!chosen?.disabled) return null;

    this.selectTarget.value = "";
    // The server's error described the length that just went; its marks go
    // with it so the page does not argue with itself.
    this.selectTarget.classList.remove("is-invalid");
    this.selectTarget.removeAttribute("aria-invalid");
    this.element.querySelector("#event_duration_minutes_error")?.remove();
    return chosen.textContent;
  }
}
