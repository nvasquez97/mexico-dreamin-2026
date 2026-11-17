const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"],
  // Native shadow DOM instead of the preset's synthetic shadow: the Sa11y
  // accessibility tests (*.accessibility.test.js, @sa11y/jest) run axe-core,
  // which walks native shadow roots but does not see every node of a
  // synthetic shadow tree (an <img> without alt went unreported).
  globals: {
    ...jestConfig.globals,
    "lwc-jest": { nativeShadow: true }
  }
};
