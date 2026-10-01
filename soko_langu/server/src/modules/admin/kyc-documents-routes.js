const { Router } = require('express');
const crypto = require('crypto');
const config = require('../../config');
const { optionalAuth } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const { presignKycDocument, DOCUMENT_IDS } = require('../media/kyc-documents');

const router = Router();

/**
 * KYC review access — deny by default.
 *
 * Two accepted proofs of "may review KYC", in this order:
 *
 *  1. `x-admin-secret`, compared timing-safely. This is the same single gate the
 *     rest of the admin panel uses (`authenticateAdmin`), so the browser panel
 *     keeps working with no change.
 *  2. A Firebase ID token whose `role` column — read from the database, never
 *     from the request body or a header — is `admin` or `super_admin`. This is
 *     what lets an admin signed into the app review a submission without ever
 *     handing the shared secret to a mobile client.
 *
 * Anything else is a 401. Nothing about the request is trusted except the
 * verified token and the server-side role lookup.
 */
function requireKycReviewer(req, res, next) {
  const secret = req.headers['x-admin-secret'];
  const expected = config.security.adminSecret;

  // Same constant-time gate as authenticateAdmin: the length comparison is the
  // gate, timingSafeEqual then cannot throw on a mismatched length.
  if (
    secret &&
    expected &&
    typeof secret === 'string' &&
    secret.length === expected.length &&
    crypto.timingSafeEqual(Buffer.from(secret), Buffer.from(expected))
  ) {
    req.kycReviewer = 'admin-secret';
    return next();
  }

  // optionalAuth already verified the token cryptographically and loaded the
  // user row; role comes from that row, not from anything the client sent.
  if (req.user && ['admin', 'super_admin'].includes(req.user.role)) {
    req.kycReviewer = `role:${req.user.role}`;
    return next();
  }

  return res.status(401).json({
    success: false,
    error: { code: 'KYC_REVIEW_REQUIRED' },
  });
}

/**
 * Temporary read URL for a submitted KYC document.
 *
 *   GET /api/v1/admin/kyc/:userId/:documentId/read-url
 *
 * `:userId` is a lookup key, never authorisation — every caller of this route
 * is already an authorised reviewer, and the resolver still verifies that the
 * key's owner segment matches the user it was requested for. The response is the
 * signed URL and its lifetime only; the bucket, account and object key stay on
 * the server so nothing here can be turned into a durable link.
 */
router.get(
  '/:userId/:documentId/read-url',
  optionalAuth,
  requireKycReviewer,
  validate({
    params: z.object({
      userId: z
        .string()
        .min(1)
        .max(128)
        .regex(/^[A-Za-z0-9_-]+$/, 'userId must be alphanumeric/-/_'),
      documentId: z.enum(DOCUMENT_IDS),
    }),
  }),
  async (req, res) => {
    try {
      const result = await presignKycDocument({
        userId: req.params.userId,
        documentId: req.params.documentId,
      });
      res.json({ success: true, data: result });
    } catch (e) {
      res.status(e.status || 500).json({
        success: false,
        error: { code: e.code || 'KYC_DOCUMENT_READ_FAILED' },
      });
    }
  },
);

module.exports = router;
module.exports.requireKycReviewer = requireKycReviewer;