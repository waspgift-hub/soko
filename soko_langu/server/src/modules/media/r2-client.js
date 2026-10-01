const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const config = require('../../config');

// R2 is S3-compatible; endpoint is derived from account id.
const R2_ENDPOINT = config.r2.accountId
  ? `https://${config.r2.accountId}.r2.cloudflarestorage.com`
  : 'https://example.r2.cloudflarestorage.com';

const s3Client = new S3Client({
  region: 'auto',
  endpoint: R2_ENDPOINT,
  credentials: {
    accessKeyId: config.r2.accessKeyId || 'unset',
    secretAccessKey: config.r2.secretAccessKey || 'unset',
  },
});

// Map logical media kind to an R2 bucket
const BUCKET_FOR_KIND = {
  image: config.r2.bucketImages,
  video: config.r2.bucketVideos,
  thumbnail: config.r2.bucketThumbnails,
  // KYC identities (passport/ID, selfie) must never sit in a bucket the media
  // Worker can reach — the Worker has no binding for this one, so a routing bug
  // there cannot expose an identity document.
  kyc: config.r2.bucketKyc,
};

// Presigned GET lifetime. Deliberately short: a KYC document is only ever shown
// to the owning seller or to an admin during review, and the link is not stored
// anywhere, so five minutes is enough to open the image and expires on its own
// even if the reviewer walks away from the screen.
const PRESIGNED_READ_TTL_SECONDS = 300;

/**
 * Verify that R2 configuration is present.
 */
function isConfigured() {
  return Boolean(config.r2.accountId && config.r2.accessKeyId && config.r2.secretAccessKey);
}

/**
 * Generate a pre-signed PUT URL so clients can upload directly to R2
 * without exposing credentials.
 */
async function createPresignedUploadUrl({ kind, key, contentType }) {
  const bucket = BUCKET_FOR_KIND[kind];
  if (!bucket) throw error(400, 'INVALID_MEDIA_KIND');
  if (!isConfigured()) throw error(503, 'R2_NOT_CONFIGURED');

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    ContentType: contentType,
  });

  const url = await getSignedUrl(s3Client, command, { expiresIn: 60 * 5 }); // 5 min
  return { url, key, bucket };
}

/**
 * Generate a presigned GET (read) URL for a private object.
 *
 * The only supported way to read a KYC identity document: there is no public URL
 * for those objects, so if a reviewer needs to see one it must come through here
 * and it stops working on its own after PRESIGNED_READ_TTL_SECONDS.
 */
async function createPresignedReadUrl({ kind, key, expiresIn } = {}) {
  const bucket = BUCKET_FOR_KIND[kind];
  if (!bucket) throw error(400, 'INVALID_MEDIA_KIND');
  if (!isConfigured()) throw error(503, 'R2_NOT_CONFIGURED');

  const command = new GetObjectCommand({ Bucket: bucket, Key: key });
  const url = await getSignedUrl(s3Client, command, {
    expiresIn: expiresIn || PRESIGNED_READ_TTL_SECONDS,
  });
  return { url, bucket };
}

/**
 * Cheap existence probe for a private object.
 *
 * Used by the presign routes to distinguish "you are not allowed" from "that
 * document does not exist" without ever handing back a signed URL for a key the
 * caller invented.
 */
async function objectExists({ kind, key }) {
  const bucket = BUCKET_FOR_KIND[kind];
  if (!bucket) return false;
  if (!isConfigured()) return false;
  try {
    await s3Client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch {
    return false;
  }
}

/**
 * Delete an object from R2.
 */
async function deleteObject({ kind, key }) {
  const bucket = BUCKET_FOR_KIND[kind];
  if (!bucket) throw error(400, 'INVALID_MEDIA_KIND');
  await s3Client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
}

module.exports = {
  s3Client,
  BUCKET_FOR_KIND,
  PRESIGNED_READ_TTL_SECONDS,
  isConfigured,
  createPresignedUploadUrl,
  createPresignedReadUrl,
  objectExists,
  deleteObject,
};

function error(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}
