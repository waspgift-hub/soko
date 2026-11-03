const pino = require('pino');

// ---------------------------------------------------------------------------
// Structured Logger
//
// WHY PINO?
// In production on Render, logs go to stdout → collected by Render's log
// pipeline. Structured JSON logs are searchable and parseable. Pino is the
// fastest Node.js logger (10x faster than Winston) which matters when
// processing thousands of webhooks per second.
// ---------------------------------------------------------------------------

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport:
    process.env.NODE_ENV !== 'production'
      ? { target: 'pino-pretty', options: { colorize: true } }
      : undefined,
  // Redact sensitive fields from logs (PCI compliance)
  redact: {
    paths: ['req.body.card', 'req.body.cvv', 'job.data.metadata.card'],
    censor: '[REDACTED]',
  },
  base: {
    pid: process.pid,
    // In Render, each service instance gets a unique hostname
    hostname: process.env.RENDER_SERVICE_NAME || 'local',
  },
});

module.exports = logger;
