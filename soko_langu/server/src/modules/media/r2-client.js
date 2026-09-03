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
};

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
 * Generate a pre-signed GET (read) URL for a private object, or a public
 * CDN URL when using the public bucket.
 */
async function createPresignedReadUrl({ kind, key }) {
  const bucket = BUCKET_FOR_KIND[kind];
  if (!bucket) throw error(400, 'INVALID_MEDIA_KIND');

  const command = new GetObjectCommand({ Bucket: bucket, Key: key });
  const url = await getSignedUrl(s3Client, command, { expiresIn: 60 * 60 }); // 1 hour
  return url;
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
  isConfigured,
  createPresignedUploadUrl,
  createPresignedReadUrl,
  deleteObject,
};

function error(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}
