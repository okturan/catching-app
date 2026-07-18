import { DateTime } from "luxon";

const MAX_DATE_RANGE_DAYS = 31;

const localDateRangeIsAllowed = (
  firstDay,
  lastDay,
  maximumDays = MAX_DATE_RANGE_DAYS,
) => {
  if (
    !DateTime.isDateTime(firstDay) ||
    !DateTime.isDateTime(lastDay) ||
    !firstDay.isValid ||
    !lastDay.isValid
  ) {
    return false;
  }

  const rangeStart = firstDay.startOf("day");
  const rangeEnd = lastDay.setZone(rangeStart.zoneName).startOf("day");
  const elapsedCalendarDays = rangeEnd.diff(rangeStart, "days").days;

  return elapsedCalendarDays >= 0 && elapsedCalendarDays < maximumDays;
};

const localDayHours = (dateTime) => {
  if (!DateTime.isDateTime(dateTime) || !dateTime.isValid) return [];

  const startOfDay = dateTime.startOf("day");
  const startOfNextDay = startOfDay.plus({ days: 1 });
  const hours = [];

  for (
    let hour = startOfDay;
    hour.toMillis() < startOfNextDay.toMillis();
    hour = hour.plus({ hours: 1 })
  ) {
    hours.push(hour);
  }

  return hours;
};

const localDayColumns = (firstDay, lastDay) => {
  if (
    !DateTime.isDateTime(firstDay) ||
    !DateTime.isDateTime(lastDay) ||
    !firstDay.isValid ||
    !lastDay.isValid
  ) {
    return [];
  }

  const rangeStart = firstDay.startOf("day");
  const rangeEnd = lastDay.setZone(rangeStart.zoneName).startOf("day");
  if (rangeEnd.toMillis() < rangeStart.toMillis()) return [];

  const columns = [];
  for (
    let day = rangeStart;
    day.toMillis() <= rangeEnd.toMillis();
    day = day.plus({ days: 1 })
  ) {
    columns.push({ day, hours: localDayHours(day) });
  }

  return columns;
};

const localHourLabels = (hours) => {
  const wallClockCounts = hours.reduce((counts, hour) => {
    const wallClock = hour.toFormat("HH:mm");
    counts.set(wallClock, (counts.get(wallClock) || 0) + 1);
    return counts;
  }, new Map());

  return hours.map((hour) => {
    const wallClock = hour.toFormat("HH:mm");
    return wallClockCounts.get(wallClock) > 1
      ? `${wallClock} (${hour.toFormat("ZZ")})`
      : wallClock;
  });
};

const timeGridDimensions = (columns) => {
  const maximumHours = columns.reduce(
    (maximum, column) => Math.max(maximum, column.hours.length),
    0,
  );

  return {
    columns: columns.length,
    rows: maximumHours === 0 ? 0 : maximumHours + 1,
  };
};

export {
  MAX_DATE_RANGE_DAYS,
  localDayColumns,
  localDayHours,
  localHourLabels,
  localDateRangeIsAllowed,
  timeGridDimensions,
};
