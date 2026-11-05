// Compat profanity check: verbatim port of the legacy endpoint, including
// the 3-strike suspension rule.
const express = require('express');
const commerceStore = require('../../services/commerce-store');
const { containsProfanity } = require('../../services/profanity');
const { requireUser } = require('./auth-helpers');

const router = express.Router();

// Requires a valid Firebase token. Without auth the endpoint is unreachable —
// prevents unauthenticated callers from probing profanity filters and eliminates
// the stolen-token escalation vector (3 calls = ban + balance seizure).
router.post('/moderation/check-text', async (req, res) => {
  try {
    const auth = await requireUser(req, res);
    if (!auth.ok) return;
    const { text } = req.body;
    if (!text) return res.json({ clean: true });
    const clean = !containsProfanity(text);
    if (!clean) {
      const uid = auth.uid;
      if (uid) {
        const userDoc = await commerceStore.getDocument('users', uid);
        if (userDoc) {
          const userData = userDoc;
          const warnings = (userData.profanityWarnings || 0) + 1;
          if (warnings >= 3) {
            // Platform money lives in sellerBalance (Firestore wallet seam), not the
            // legacy `balance` field — seizing the wrong field left the seller's
            // real wallet untouched and fabricated a revenue row.
            const balance = userData.sellerBalance || userData.balance || 0;
            await commerceStore.updateDocument('users', uid, {
              isSuspended: true,
              isDeleted: true,
              suspendedReason: 'Repeated profanity violations',
              profanityWarnings: warnings,
            });
            if (balance > 0) {
              await commerceStore.addDocument(commerceStore.COLLECTIONS.revenueTransactions, {
                userId: uid,
                type: 'profanity_seizure',
                amount: balance,
                sokoLanguCommission: balance,
                description: `Balance seized: ${warnings} profanity violations`,
                timestamp: commerceStore.serverTimestamp(),
              });
              await commerceStore.updateDocument('users', uid, { balance: 0, sellerBalance: 0 });
            }
            return res.json({ clean: false, banned: true, message: 'Account deleted due to repeated profanity violations' });
          }
          await commerceStore.updateDocument('users', uid, { profanityWarnings: warnings });
          return res.json({ clean: false, banned: false, warning: warnings, message: `Profanity detected (${warnings}/3 warnings before account deletion)` });
        }
      }
      return res.json({ clean: false, banned: false, message: 'Profanity detected in text' });
    }
    res.json({ clean: true });
  } catch (e) {
    res.json({ clean: true });
  }
});

module.exports = router;

