const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const uploadService = require('./upload-service');

const router = Router();

// Request a signed upload URL (image or video)
router.post(
  '/upload-url',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      kind: z.enum(['image', 'video', 'thumbnail']),
      contentType: z.string().min(1).max(100),
      ownerType: z.string().min(1).max(30),
      ownerId: z.string().uuid(),
    }),
  }),
  async (req, res) => {
    const session = await uploadService.createUploadSession({
      kind: req.body.kind,
      contentType: req.body.contentType,
      ownerType: req.body.ownerType,
      ownerId: req.body.ownerId,
    });
    res.status(201).json({ success: true, data: session });
  }
);

module.exports = router;
