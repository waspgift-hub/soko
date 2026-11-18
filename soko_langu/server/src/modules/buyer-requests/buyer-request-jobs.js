const service = require('./request-service');

async function runBuyerRequestJobs() {
  try {
    return await service.runExpirySweep(Date.now());
  } catch (e) {
    console.error('[BUYER-REQUESTS] sweep failed:', e?.message || e);
    return { expired: 0, notified: 0, error: e?.message };
  }
}

module.exports = { runBuyerRequestJobs };