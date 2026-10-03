const { defineConfig } = require('cypress');
const { applications } = require('../../platform.json');
module.exports = defineConfig({
  e2e: {
    baseUrl: `http://localhost:${applications.web.localPort}`,
    specPattern: 'browser/**/*.cy.js',
    supportFile: false,
    fixturesFolder: false,
  },
  video: false,
});
