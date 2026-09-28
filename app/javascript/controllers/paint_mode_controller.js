import { Controller } from "@hotwired/stimulus";

const STORAGE_KEY = "catching-app.paint-mode";

// Scroll or Paint, for a finger on the grid; a mouse always paints. The
// choice is remembered on this device and written on the grid, where the
// painter reads it and the stylesheet stops the page panning while painting.
export default class extends Controller {
  static targets = ["grid", "switch"];

  connect() {
    this.apply(this.remembered() || "scroll");
  }

  choose({ target }) {
    this.apply(target.value);
    try {
      window.localStorage.setItem(STORAGE_KEY, target.value);
    } catch (_error) {
      // Storage may be unavailable; the choice lasts for this page.
    }
  }

  apply(mode) {
    this.switchTarget.querySelectorAll("input[type=radio]").forEach((input) => {
      input.checked = input.value === mode;
    });
    this.switchTarget.dataset.mode = mode;
    this.gridTarget.dataset.paintMode = mode;
    this.gridTarget.classList.toggle("mode-paint", mode === "paint");
  }

  remembered() {
    try {
      const mode = window.localStorage.getItem(STORAGE_KEY);
      return mode === "paint" || mode === "scroll" ? mode : null;
    } catch (_error) {
      return null;
    }
  }
}
