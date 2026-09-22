import { application } from "./application";

import AvailabilityController from "./availability_controller";
import ClockWallController from "./clock_wall_controller";
import DefinerController from "./definer_controller";
import ErrorSummaryController from "./error_summary_controller";

application.register("availability", AvailabilityController);
application.register("clock-wall", ClockWallController);
application.register("definer", DefinerController);
application.register("error-summary", ErrorSummaryController);
