import "@hotwired/turbo-rails";
import "bootstrap/js/dist/alert";
import "bootstrap/js/dist/collapse";

import { initClockWall } from "./components/clock_wall";
import { initTimeSlotDefiner } from "./components/time_slot_definer";
import { initTimeSlotShow } from "./components/time_slot_show";

document.addEventListener("turbo:load", () => {
  initClockWall();
  initTimeSlotDefiner();
  initTimeSlotShow();
});
