import "@hotwired/turbo-rails";
import "bootstrap/js/dist/alert";
import "bootstrap/js/dist/collapse";

import { initDashboardTabs } from "./components/dashboard_tabs";
import { initHomeCarousel } from "./components/home_carousel";
import { initTimeSlotDefiner } from "./components/time_slot_definer";
import { initTimeSlotShow } from "./components/time_slot_show";

document.addEventListener("turbo:load", () => {
  initDashboardTabs();
  initHomeCarousel();
  initTimeSlotDefiner();
  initTimeSlotShow();
});
