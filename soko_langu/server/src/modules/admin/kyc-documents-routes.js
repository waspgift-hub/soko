const { Router } = require('express');
const crypto = require('crypto');
const config = require('../../config');
const { optionalAuth } = require('../../middleware/auth');
const { can } = require('../../middleware/admin-rbac');
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
function isBootstrapSuperAdminEmail(email) {
  if (!email) return false;
  const list = config.security && config.security.superAdminEmails;
  return Array.isArray(list) && list.includes(String(email).trim().toLowerCase());
}

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

  // Staff session token (admin_staff + staff_sessions). Reviewed here as well
  // as by authenticateAdmin so a KYC reviewer can work from the panel without
  // the owner's break-glass secret. Permission is checked against the same
  // role matrix (`kyc:read`) rather than a second hand-written role list.
  const staffToken = req.headers['x-staff-token'];
  if (staffToken && typeof staffToken === 'string' && /^[a-f0-9]{32,128}$/i.test(staffToken)) {
    return (async () => {
      try {
        const commerceStore = require('../../services/commerce-store');
        const session = await commerceStore.getDocument('staff_sessions', staffToken);
        if (!session) return res.status(401).json({ success: false, error: { code: 'KYC_REVIEW_REQUIRED' } });
        const expiresMs = session.expiresAtMs
          ? Number(session.expiresAtMs)
          : new Date(session.expiresAt || 0).getTime();
        if (!Number.isFinite(expiresMs) || expiresMs < Date.now()) {
          return res.status(401).json({ success: false, error: { code: 'STAFF_SESSION_EXPIRED' } });
        }
        const staff = await commerceStore.getDocument('admin_staff', session.staffId);
        if (!staff || staff.active === false) {
          return res.status(403).json({ success: false, error: { code: 'STAFF_INACTIVE' } });
        }
        const principal = {
          adminStaff: {
            id: session.staffId,
            role: staff.role || session.role || 'support',
            permissions: Array.isArray(staff.permissions) ? staff.permissions : [],
          },
        };
        if (can(principal, 'kyc:read') || can(principal, 'kyc:write')) {
          req.kycReviewer = `staff:${principal.adminStaff.id}`;
          return next();
        }
        return res.status(403).json({ success: false, error: { code: 'KYC_PERMISSION_REQUIRED' } });
      } catch (e) {
        console.error('[AUTH] KYC staff session lookup failed:', e && e.message);
        return res.status(503).json({ success: false, error: { code: 'AUTH_SERVICE_UNAVAILABLE' } });
      }
    })();
  }

  // optionalAuth already verified the token cryptographically and loaded the
  // user row; role comes from that row, not from anything the client sent.
  if (req.user && (['admin', 'super_admin', 'kyc_reviewer'].includes(req.user.role) || isBootstrapSuperAdminEmail(req.user.email))) {
    req.kycReviewer = `role:${req.user.role || 'super_admin'}`;
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