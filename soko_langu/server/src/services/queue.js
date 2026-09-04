const { Queue } = require('bullmq');
const { getRedis } = require('../config/redis');

let mediaQueue = null;

function getMediaQueue() {
  if (!mediaQueue) {
    const connection = getRedis();
    mediaQueue = new Queue('media', { connection });
  }
  return mediaQueue;
}

async function closeMediaQueue() {
  if (mediaQueue) {
    await mediaQueue.close();
    mediaQueue = null;
  }
}

module.exports = { getMediaQueue, closeMediaQueue };
