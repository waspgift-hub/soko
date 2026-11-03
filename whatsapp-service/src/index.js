const config = require('./config');
const { createApp } = require('./app');

const app = createApp();

app.listen(config.port, () => {
  console.log(`whatsapp-service listening on port ${config.port} (API ${config.version})`);
  if (!config.isConfigured) console.warn('Warning: USER_ACCESS_TOKEN or PHONE_NUMBER_ID is missing');
  if (!config.apiKey) console.warn('Warning: API_KEY is empty, the API is open to anyone who can reach it');
});
