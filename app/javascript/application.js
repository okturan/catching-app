import "@hotwired/turbo-rails";
import "bootstrap/js/dist/alert";
import "bootstrap/js/dist/collapse";

import { initClockWall } from "./components/clock_wall";
import { initErrorSummary } from "./components/error_summary";
import { initTimeSlotDefiner } from "./components/time_slot_definer";
import { initTimeSlotShow } from "./components/time_slot_show";

// Turbo fires turbo:load on a visit, but a form's own 4xx response is rendered
// without one — only turbo:render. Booting on both is what makes a 422 page
// live: the definer rebuilds the grid from the echoed #time_slot_array instead
// of leaving an empty table, and the error summary takes focus. Every init
// aborts the listeners it registered last time, so a visit that fires both
// events initializes once and binds once.
const boot = () => {
  initClockWall();
  initErrorSummary();
  initTimeSlotDefiner();
  initTimeSlotShow();
};

document.addEventListener("turbo:load", boot);
document.addEventListener("turbo:render", boot);
