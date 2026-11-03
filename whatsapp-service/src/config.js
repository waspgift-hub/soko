require('dotenv').config();

const config = {
  port: Number(process.env.PORT || 3000),
  version: process.env.VERSION || 'v25.0',
  phoneNumberId: process.env.PHONE_NUMBER_ID || '',
  accessToken: process.env.USER_ACCESS_TOKEN || '',
  apiKey: process.env.API_KEY || '',
  rateLimitPerMinute: Number(process.env.RATE_LIMIT_PER_MINUTE || 60),
  bulkMaxRecipients: Number(process.env.BULK_MAX_RECIPIENTS || 500),
  bulkConcurrency: Number(process.env.BULK_CONCURRENCY || 5),
  defaultCountryCode: process.env.DEFAULT_COUNTRY_CODE || '255',
  logFile: process.env.LOG_FILE || 'logs/messages.log',
};

config.graphBase = `https://graph.facebook.com/${config.version}`;
config.isConfigured = Boolean(config.accessToken && config.phoneNumberId);

module.exports = config;
