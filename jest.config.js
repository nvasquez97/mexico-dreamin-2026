const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    // CSS-only module (shared brand stylesheet) imported with @import 'c/rcBrand'
    "^c/rcBrand$": "<rootDir>/force-app/main/default/lwc/rcBrand/rcBrand.css"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
