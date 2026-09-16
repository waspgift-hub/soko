const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const notificationService = require('./notification-service');

const router = Router();

// List notifications (paginated, newest first)
router.get('/', authenticate, async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const limit = parseInt(req.query.limit || '20', 10);
    const result = await notificationService.listNotifications(req.user.id, { page, limit });
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'NOTIFICATION_LIST_FAILED', message: e.message } });
  }
});

// Unread count
router.get('/unread-count', authenticate, async (req, res) => {
  try {
    const count = await notificationService.unreadCount(req.user.id);
    res.json({ success: true, data: { count } });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'NOTIFICATION_COUNT_FAILED', message: e.message } });
  }
});

// Mark a single notification read
router.post('/:id/read', authenticate, async (req, res) => {
  try {
    const ok = await notificationService.markRead(req.user.id, req.params.id);
    if (!ok) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Notification not found' } });
    res.json({ success: true, data: { marked: true } });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'NOTIFICATION_READ_FAILED', message: e.message } });
  }
});

// Mark all notifications read
router.post('/read-all', authenticate, async (req, res) => {
  try {
    const count = await notificationService.markAllRead(req.user.id);
    res.json({ success: true, data: { marked: count } });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'NOTIFICATION_READ_ALL_FAILED', message: e.message } });
  }
});

// Delete a single notification
router.delete('/:id', authenticate, async (req, res) => {
  try {
    const ok = await notificationService.deleteNotification(req.user.id, req.params.id);
    if (!ok) return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Notification not found' } });
    res.json({ success: true, data: { deleted: true } });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'NOTIFICATION_DELETE_FAILED', message: e.message } });
  }
});

// Delete all notifications
router.delete('/', authenticate, async (req, res) => {
  try {
    const count = await notificationService.deleteAll(req.user.id);
    res.json({ success: true, data: { deleted: count } });
  } catch (e) {
    res.status(500).json({ success: false, error: { code: 'NOTIFICATION_DELETE_ALL_FAILED', message: e.message } });
  }
});

module.exports = router;
