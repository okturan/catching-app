import { Controller } from "@hotwired/stimulus";

import { rewriteZonedInstants } from "../lib/zoned_label";
import { browserTimeZone } from "../lib/zones";

// Times the server rendered in each event's own zone, read in the visitor's.
export default class extends Controller {
  connect() {
    rewriteZonedInstants(this.element, browserTimeZone);
  }
}
