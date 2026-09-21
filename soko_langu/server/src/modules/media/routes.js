const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const uploadService = require('./upload-service');

const router = Router();

// ownerType only namespaces the R2 object key (media/<kind>/<ownerType>/...),
// so it is an allow-list — never free-form — to keep the namespace clean.
const OWNER_TYPES = ['product', 'user', 'seller', 'feed', 'dispute', 'chat'];
// ownerId is a namespace segment too: products upload media BEFORE the Product
// row exists (seller picks images first, then submits the listing), so it must
// accept a Firebase UID or a Postgres uuid — not just a uuid.
const OWNER_ID = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[A-Za-z0-9][A-Za-z0-9_-]*$/, 'ownerId must be alphanumeric/-/_');

// Request a signed upload URL (image or video)
router.post(
  '/upload-url',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      kind: z.enum(['image', 'video', 'thumbnail']),
      contentType: z.string().min(1).max(100),
      ownerType: z.enum(OWNER_TYPES),
      ownerId: OWNER_ID,
    }),
  }),
  async (req, res) => {
    const session = await uploadService.createUploadSession({
      kind: req.body.kind,
      contentType: req.body.contentType,
      ownerType: req.body.ownerType,
      ownerId: req.body.ownerId,
    });
    // Queue a post-upload processing job (image thumbnail / video transcode).
    // Best-effort: upload URL already returned, job failure never blocks it.
    try {
      const { getMediaQueue } = require('../../services/queue');
      const queue = getMediaQueue();
      await queue.add(req.body.kind === 'video' ? 'video-transcode' : 'image', {
        r2Key: session.r2Key,
        thumbnailR2Key: session.thumbnailR2Key || null,
        ownerType: req.body.ownerType,
        ownerId: req.body.ownerId,
        kind: req.body.kind,
      });
    } catch (e) {
      console.error('[MEDIA] queue failed:', e.message);
    }
    res.status(201).json({ success: true, data: session });
  }
);

module.exports = router;
