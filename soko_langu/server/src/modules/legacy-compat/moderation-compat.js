// Compat profanity check: verbatim port of the legacy endpoint, including
// the 3-strike suspension rule.
const express = require('express');
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../../config/firebase');
const { containsProfanity } = require('../../services/profanity');

const router = express.Router();

router.post('/moderation/check-text', async (req, res) => {
  try {
    const { text } = req.body;
    if (!text) return res.json({ clean: true });
    const clean = !containsProfanity(text);
    if (!clean) {
      const authHeader = req.headers['authorization'];
      let uid = null;
      if (authHeader && authHeader.startsWith('Bearer ')) {
        try {
          uid = (await admin.auth().verifyIdToken(authHeader.slice(7))).uid;
        } catch {}
      }
      const db = getFirebaseFirestore();
      if (uid && db) {
        const userRef = db.collection('users').doc(uid);
        const userDoc = await userRef.get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          const warnings = (userData.profanityWarnings || 0) + 1;
          if (warnings >= 3) {
            const balance = userData.balance || 0;
            await userRef.update({
              isSuspended: true,
              isDeleted: true,
              suspendedReason: 'Repeated profanity violations',
              profanityWarnings: warnings,
            });
            if (balance > 0) {
              await db.collection('revenue_transactions').add({
                userId: uid,
                type: 'profanity_seizure',
                amount: balance,
                sokoLanguCommission: balance,
                description: `Balance seized: ${warnings} profanity violations`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
              });
              await userRef.update({ balance: 0 });
            }
            return res.json({ clean: false, banned: true, message: 'Account deleted due to repeated profanity violations' });
          }
          await userRef.update({ profanityWarnings: warnings });
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
