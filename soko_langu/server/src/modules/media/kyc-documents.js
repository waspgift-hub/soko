const { getStore } = require('../../config/database');
const { createPresignedReadUrl, objectExists, PRESIGNED_READ_TTL_SECONDS } = require('./r2-client');
const { isKycKey, kycKeyOwner } = require('./upload-service');

/**
 * Private KYC document reads.
 *
 * A KYC identity document (passport/ID photo, selfie, shop video) is written
 * once to the private `soko-vibe-kyc` bucket under `kyc/<owner>/<id>/<uuid>.<ext>`
 * and is never given a public URL. There is exactly one way to look at one:
 * a short-lived presigned GET minted by this module, after the caller has been
 * authorised. The signed URL is never written to the database.
 *
 * The database stores the object KEY, not a URL. That is deliberate: a URL
 * would either expire (making the stored row dead) or, worse, be a permanent
 * public link — which is the bug this module exists to prevent.
 */

/** URL/field name a caller may ask for, mapped to its column on the KYC row. */
const DOCUMENT_FIELDS = {
  idImage: 'idImageUrl',
  selfie: 'selfieUrl',
  shopVideo: 'shopVideoUrl',
};

const DOCUMENT_IDS = Object.keys(DOCUMENT_FIELDS);

/**
 * Pull the R2 object key out of whatever the column happens to hold.
 *
 * Accepts the bare key we now write, or a public media URL containing one (so a
 * row written before this change still resolves). Returns null for anything
 * that is not a private-namespace KYC key — including legacy Cloudinary URLs,
 * which are deliberately NOT translated into a servable link here.
 */
function toKycKey(stored) {
  if (typeof stored !== 'string') return null;
  const raw = stored.trim();
  if (!raw) return null;
  if (isKycKey(raw)) return raw;

  // Only accept a public URL that still points into the private namespace.
  const asUrl = raw.replace(/^https?:\/\/[^/]+\//i, '');
  return isKycKey(asUrl) ? asUrl : null;
}

function error(status, code) {
  const e = new Error(code);
  e.status = status;
  e.code = code;
  return e;
}

/**
 * Resolve one of `userId`'s KYC documents to a verified, presigned read URL.
 *
 * Every guard is here rather than at the call sites so the owner route and the
 * admin route cannot drift apart:
 *  - the document id must be a known field;
 *  - the row must exist and the column must be filled;
 *  - the stored value must resolve to a strict `kyc/…` key;
 *  - the key's owner segment must equal the requested user;
 *  - the object must actually exist in the private bucket;
 *  - only then is a signed URL produced.
 *
 * `expectOwnerUid` is the authenticated caller's own uid. Pass it for self-service
 * reads so a mismatched row cannot be read even if the id were guessed; omit it
 * only when the caller has already been authorised as an admin out of band.
 */
async function presignKycDocument({ userId, documentId, expectOwnerUid }) {
  if (!userId || !DOCUMENT_FIELDS[documentId]) throw error(400, 'INVALID_DOCUMENT_ID');
  if (expectOwnerUid && expectOwnerUid !== userId) throw error(403, 'NOT_YOUR_DOCUMENT');

  const store = getStore();
  const row = await store.kycApplication.findUnique({ where: { userId } });
  if (!row) throw error(404, 'NO_KYC_APPLICATION');

  const stored = row[DOCUMENT_FIELDS[documentId]];
  if (!stored) throw error(404, 'DOCUMENT_NOT_SUBMITTED');

  const key = toKycKey(stored);
  if (!key) {
    // A row that predates private storage (e.g. an old Cloudinary URL). We do
    // not manufacture a link for it — an admin needs to know it is not in the
    // private store rather than silently receiving a public one.
    throw error(409, 'DOCUMENT_NOT_IN_PRIVATE_STORE');
  }

  const owner = kycKeyOwner(key);
  if (!owner || owner !== userId) throw error(403, 'DOCUMENT_OWNER_MISMATCH');

  const exists = await objectExists({ kind: 'kyc', key });
  if (!exists) throw error(404, 'DOCUMENT_NOT_FOUND');

  const { url } = await createPresignedReadUrl({ kind: 'kyc', key });
  // Only the temporary URL and its lifetime leave this module. No bucket name,
  // no account id, no key — nothing that helps rebuild a permanent link.
  return { url, expiresIn: PRESIGNED_READ_TTL_SECONDS, documentId };
}

module.exports = {
  DOCUMENT_FIELDS,
  DOCUMENT_IDS,
  toKycKey,
  presignKycDocument,
  PRESIGNED_READ_TTL_SECONDS,
};