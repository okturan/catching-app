const MomentLocalesPlugin = require("moment-locales-webpack-plugin");
const MomentTimezoneDataPlugin = require("moment-timezone-data-webpack-plugin");

module.exports = {
  plugins: [
    // To strip all locales except “en”
    new MomentLocalesPlugin(),

    // Or: To strip all locales except “en”, “es-us” and “ru”
    // (“en” is built into Moment and can’t be removed)
    new MomentLocalesPlugin({
      localesToKeep: ["es", "ru", "tr", "ar", "az"],
    }),
  ],
};

module.exports = {
  plugins: [
    new MomentTimezoneDataPlugin({
      startYear: currentYear - 5,
      endYear: currentYear + 5,
    }),
  ],
};
