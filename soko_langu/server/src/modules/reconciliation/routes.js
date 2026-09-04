const { Router } = require('express');
const { authenticate, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const service = require('./reconciliation-service');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

router.use(authenticate, verifyAdmin);

// Run a reconciliation for a period (admin)
router.post(
  '/run',
  validate({
    body: z.object({
      provider: z.string().default('clickpesa'),
      periodStart: z.string().datetime(),
      periodEnd: z.string().datetime(),
    }),
  }),
  async (req, res) => {
    try {
      const row = await service.runReconciliation(req.body);
      await writeAudit({
        ...auditFromReq(req),
        action: 'reconciliation.run',
        entityType: 'reconciliation',
        entityId: row.id,
        newState: { status: row.status },
      });
      res.status(201).json({ success: true, data: row });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Reconciliation failed' });
    }
  }
);

// List past runs (admin)
router.get(
  '/',
  validate({
    query: z.object({
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    const data = await service.listReconciliations(req.query);
    res.json({ success: true, data });
  }
);

module.exports = router;
