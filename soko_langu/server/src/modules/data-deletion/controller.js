const { getStore } = require('../../config/database');
const { writeAudit } = require('../../services/audit');

// Public web-form account/data deletion request. No Firebase account is
// required — the submitter's contact detail is captured and an admin later
// reconciles it against Firestore users before deleting any data (privacy
// policy 7.2: 30-day cooling-off before permanent deletion).
async function createRequest(req, res) {
  try {
    const { fullName, email, phone, reason } = req.body;
    const store = getStore();

    const doc = await store.dataDeletionRequest.create({
      data: {
        fullName: fullName || null,
        email,
        phone: phone || null,
        reason: reason || null,
        status: 'new',
        source: 'web_form',
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || null,
      },
    });

    await writeAudit({
      actorId: null,
      actorType: 'public',
      action: 'DATA_DELETION_REQUESTED',
      entityType: 'dataDeletionRequest',
      entityId: doc.id,
      newState: { status: 'new', email },
      ipAddress: req.ip,
      userAgent: req.headers['user-agent'] || null,
    });

    res.status(201).json({
      success: true,
      requestId: doc.id,
      message: 'Data deletion request received. We will process it within 30 days.',
    });
  } catch (error) {
    console.error('[DATA-DELETION] create error:', error.message);
    res.status(500).json({ error: 'Failed to submit deletion request' });
  }
}

module.exports = { createRequest };