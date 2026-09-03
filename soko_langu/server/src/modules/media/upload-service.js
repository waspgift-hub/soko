const crypto = require('crypto');
const { createPresignedUploadUrl, isConfigured } = require('./r2-client');

const ALLOWED_KINDS = ['image', 'video', 'thumbnail'];
const MAX_IMAGE_UPLOAD_GB = 0.05; // 50 MB
const MAX_VIDEO_UPLOAD_GB = 0.5; // 500 MB

/**
 * Create an upload session: returns a pre-signed PUT URL so clients can
 * upload directly to R2 without exposing credentials.
 * The caller associates the returned key with the owning entity (Product, Feed, User).
 */
async function createUploadSession({ kind, contentType, ownerType, ownerId }) {
  if (!ALLOWED_KINDS.includes(kind)) throw error(400, 'INVALID_MEDIA_KIND');
  if (!isConfigured()) throw error(503, 'R2_NOT_CONFIGURED');

  // Object naming convention: <kind>s/<ownerType>/<ownerId>/<random>.<ext>
  const ext = extensionFor(contentType);
  const key = `${kind}s/${ownerType}/${ownerId}/${crypto.randomUUID()}${ext}`;

  const { url, bucket } = await createPresignedUploadUrl({ kind, key, contentType });

  return { uploadUrl: url, key, bucket, kind };
}

function extensionFor(contentType) {
  const map = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'video/mp4': '.mp4',
  };
  return map[contentType] || '.bin';
}

function error(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

module.exports = {
  ALLOWED_KINDS,
  MAX_IMAGE_UPLOAD_GB,
  MAX_VIDEO_UPLOAD_GB,
  createUploadSession,
};
