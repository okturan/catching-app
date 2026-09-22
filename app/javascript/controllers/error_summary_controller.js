import { Controller } from "@hotwired/stimulus";

// Moves focus to the 422 summary, so a keyboard or screen-reader visitor lands
// on what went wrong instead of at the top of a page that looks unchanged.
export default class extends Controller {
  connect() {
    this.element.focus();
  }
}
