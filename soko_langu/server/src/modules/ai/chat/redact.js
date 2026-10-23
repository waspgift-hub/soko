// Strips credentials from message text before it is persisted or sent to a model.
//
// The spec forbids storing passwords, OTPs, payment secrets and auth tokens in
// messages (§4) and in chat memory (§6). memory-extractor.js enforces the
// memory half; this enforces the message half, at the single choke point every
// message passes through.
//
// Redaction replaces with a marker rather than deleting, so the user reopening the
// conversation can see that something was there and understand why the AI behaved
// as if it had not received a value — a silently shortened message reads as a bug.
// Crucially the ORIGINAL text is never stored anywhere: what reaches Firestore and
// what reaches the provider are both this redacted form.
//
// This is a safety net, not a guarantee. A secret phrased in a way no pattern
// anticipates ("my pin is one nine four one") passes through. That is accepted,
// because the alternative — refusing or mangling arbitrary user text — would break
// normal chat, and because the real fix for a credential being pasted into a chat
// is the same as for any leak: rotate it.

const { SENSITIVE_PATTERNS } = require('./memory-extractor');

const MARKER = '[redacted]';

/**
 * Returns [text] with every recognised credential shape replaced.
 *
 * Order matters only in that the specific patterns must run before the generic
 * digit-range one, otherwise a 16-digit card number is caught by a looser rule and
 * the more informative `card` label is lost. The list is already ordered that way.
 */
function redactSecrets(text) {
  let out = String(text == null ? '' : text);
  for (const pattern of SENSITIVE_PATTERNS) {
    out = out.replace(pattern.re, (match) => {
      // Keep only the leading label ("password", "OTP", etc.) so the message still
      // reads sensibly, and drop the value entirely. The value is the secret.
      const label = match.split(/\s+/)[0].replace(/[^a-zA-Z]/g, '');
      return label ? `${label.toLowerCase()}: ${MARKER}` : MARKER;
    });
  }
  return out;
}

/** True when redaction would change [text]; used to skip pointless writes. */
function hasSecrets(text) {
  return redactSecrets(text) !== String(text == null ? '' : text);
}

module.exports = { redactSecrets, hasSecrets, MARKER };