const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    "^c/rcStyles$": "<rootDir>/jest-mocks/rcStyles.js"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
