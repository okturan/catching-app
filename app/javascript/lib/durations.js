// A planned length must be a whole number of slots. Splits the offered
// lengths (numbers or numeric strings) by that rule for the given step.
const allowedDurations = (stepMinutes, options) => {
  const step = Number(stepMinutes);
  const allowed = [];
  const disallowed = [];

  options.forEach((option) => {
    const minutes = Number(option);
    const fits =
      Number.isInteger(step) && step > 0 && Number.isInteger(minutes) && minutes > 0 && minutes % step === 0;
    (fits ? allowed : disallowed).push(option);
  });

  return { allowed, disallowed };
};

export { allowedDurations };
