const { Router } = require('express');
const { authenticate, requireActive, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const service = require('./moderation-service');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

function serviceError(res, e) {
  return res.status(e.status || 500).json({ error: e.message || 'Moderation operation failed' });
}

// Submit a report (authenticated users)
router.post(
  '/',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      reportedUserId: z.string().min(1),
      reportedUserName: z.string().max(100).optional(),
      reporterName: z.string().max(100).optional(),
      productId: z.string().optional(),
      productName: z.string().max(200).optional(),
      reason: z.string().min(1).max(50),
      description: z.string().min(1).max(2000),
    }),
  }),
  async (req, res) => {
    try {
      const report = await service.submitReport({
        reporterUid: req.firebaseUid,
        reporterName: req.body.reporterName,
        reportedUserId: req.body.reportedUserId,
        reportedUserName: req.body.reportedUserName,
        productId: req.body.productId,
        productName: req.body.productName,
        reason: req.body.reason,
        description: req.body.description,
      });
      res.status(201).json({ success: true, data: { id: report.id } });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

// List reports (admin)
router.get(
  '/',
  authenticate,
  verifyAdmin,
  validate({
    query: z.object({
      status: z.string().optional(),
      targetType: z.string().optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const data = await service.listReports(req.query);
    res.json({ success: true, data });
  }
);

// Review a report (admin)
router.put(
  '/:id/review',
  authenticate,
  verifyAdmin,
  validate({
    body: z.object({
      status: z.enum(['reviewed', 'actioned', 'dismissed']),
    }),
  }),
  async (req, res) => {
    try {
      const report = await service.reviewReport({
        id: req.params.id,
        status: req.body.status,
        reviewedBy: req.user.id,
      });
      await writeAudit({
        ...auditFromReq(req),
        action: 'moderation.review',
        entityType: 'moderation_report',
        entityId: report.id,
        newState: { status: req.body.status },
      });
      res.json({ success: true, data: report });
    } catch (e) {
      serviceError(res, e);
    }
  }
);

module.exports = router;
