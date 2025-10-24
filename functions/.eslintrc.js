/*module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2018,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
  },
  overrides: [
    {
      files: ["**//*.spec.*"],
/*      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
}; */

module.exports = {
  env: { es6: true, node: true },
  parserOptions: { ecmaVersion: 2020 },
  extends: ["eslint:recommended", "google"],
  rules: {
    // keep code readable but not overly strict
    "require-jsdoc": "off",
    "max-len": ["error", { code: 120, ignoreUrls: true, ignoreStrings: true, ignoreTemplateLiterals: true }],
    "object-curly-spacing": ["error", "always"],
    "comma-dangle": "off",
    "quotes": ["error", "double", { avoidEscape: true }],
    "indent": ["error", 2],
    // optional: remove this if it ever complains about 'name' or 'length'
    "no-restricted-globals": ["off"],
  },
};
