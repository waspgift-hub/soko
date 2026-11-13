const crypto = require('crypto');
const { createPresignedUploadUrl, isConfigured } = require('./r2-client');

const ALLOWED_KINDS = ['image', 'video', 'thumbnail', 'kyc'];
const MAX_IMAGE_UPLOAD_GB = 0.05; // 50 MB
const MAX_VIDEO_UPLOAD_GB = 0.5; // 500 MB

/**
 * KYC identity documents get their own key namespace: `kyc/<ownerType>/…`
 * rather than the pluralised `<kind>s/…` used for public media, and the segment
 * is the literal `kyc` so both the media Worker and any future tooling can
 * recognise and refuse the namespace from the key alone.
 *
 * This is a namespacing rule, NOT an access control. Authorisation lives in
 * routes.js (owner may only upload under their own id) and in the presign-read
 * routes; the key itself is never treated as proof of anything.
 */
const KYC_KEY_PREFIX = 'kyc';

// Owner namespaces a KYC document may be filed under. KYC belongs to a person,
// so `product`/`seller`/`feed`/`chat` are meaningless here and are refused
// rather than silently ignored.
const KYC_OWNER_TYPES = ['user'];

/**
 * Create an upload session: returns a pre-signed PUT URL so clients can
 * upload directly to R2 without exposing credentials.
 * The caller associates the returned key with the owning entity (Product, Feed, User).
 *
 * @param {string} requestedOwnerId Caller-supplied owner. For KYC this is
 *   IGNORED and replaced with the caller's own authenticated uid — a client that
 *   asks to file an identity document under someone else's id gets nowhere.
 */
async function createUploadSession({ kind, contentType, ownerType, ownerId, callerUid }) {
  if (!ALLOWED_KINDS.includes(kind)) throw error(400, 'INVALID_MEDIA_KIND');
  if (!isConfigured()) throw error(503, 'R2_NOT_CONFIGURED');

  let safeOwnerType = ownerType;
  let safeOwnerId = ownerId;

  if (kind === 'kyc') {
    if (!KYC_OWNER_TYPES.includes(ownerType)) throw error(400, 'INVALID_MEDIA_OWNER');
    // Trust the verified session, never the payload.
    if (!callerUid) throw error(401, 'AUTH_REQUIRED');
    safeOwnerType = ownerType;
    safeOwnerId = callerUid;
  }

  // Object naming convention: <kind>s/<ownerType>/<ownerId>/<random>.<ext>
  const ext = extensionFor(contentType);
  const key =
    kind === 'kyc'
      ? `${KYC_KEY_PREFIX}/${safeOwnerType}/${safeOwnerId}/${crypto.randomUUID()}${ext}`
      : `${kind}s/${safeOwnerType}/${safeOwnerId}/${crypto.randomUUID()}${ext}`;

  const { url, bucket } = await createPresignedUploadUrl({ kind, key, contentType });

  return { uploadUrl: url, key, bucket, kind };
}

/**
 * True when `key` belongs to the private KYC namespace.
 *
 * Every presign-read path gates on this. It is intentionally strict — anything
 * that is not exactly `kyc/<owner>/<id>/<uuid>.<ext>` is not a KYC key, so a
 * crafted or legacy key can never be signed.
 */
function isKycKey(key) {
  return typeof key === 'string' && /^kyc\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/[0-9a-f-]{36}\.[a-z0-9]{2,5}$/.test(key);
}

/**
 * Extract the owner segment of a KYC key, or null when it is not a KYC key.
 */
function kycKeyOwner(key) {
  return isKycKey(key) ? key.split('/')[2] : null;
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
  KYC_KEY_PREFIX,
  KYC_OWNER_TYPES,
  MAX_IMAGE_UPLOAD_GB,
  MAX_VIDEO_UPLOAD_GB,
  createUploadSession,
  isKycKey,
  kycKeyOwner,
};
