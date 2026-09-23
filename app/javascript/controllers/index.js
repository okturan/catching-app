import { application } from "./application";

import AvailabilityController from "./availability_controller";
import ClockWallController from "./clock_wall_controller";
import DefinerController from "./definer_controller";
import DurationController from "./duration_controller";
import ErrorSummaryController from "./error_summary_controller";
import PaintModeController from "./paint_mode_controller";
import ZonedTimesController from "./zoned_times_controller";

application.register("availability", AvailabilityController);
application.register("clock-wall", ClockWallController);
application.register("definer", DefinerController);
application.register("duration", DurationController);
application.register("error-summary", ErrorSummaryController);
application.register("paint-mode", PaintModeController);
application.register("zoned-times", ZonedTimesController);
