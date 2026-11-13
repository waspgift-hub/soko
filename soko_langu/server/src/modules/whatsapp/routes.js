const express = require('express');
const { verifyChallenge, receiveEvent } = require('./webhook-controller');

const router = express.Router();

// Meta sends the verification as GET; the signature check does not apply here.
router.get('/', verifyChallenge);
// Meta posts deliveries with raw bytes so X-Hub-Signature-256 can be verified
// against the exact payload. Using express.raw here avoids re-serialisation.
router.post('/', express.raw({ type: 'application/json', limit: '1mb' }), receiveEvent);

module.exports = router;
