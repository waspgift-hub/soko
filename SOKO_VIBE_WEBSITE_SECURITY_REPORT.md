# SOKO VIBE WEBSITE — SECURITY REPORT

**Date:** 2026-11-09

## Controls Present / Added

- **No frontend secrets:** Waitlist/contact use same-origin API (`/api/v1/...`). No Firebase Admin, SMTP, Resend, or private keys in static site. No analytics/tracking added.
- **Input validation:** Client-side validation for email, contact required fields, consent; server-side Zod validation for `/api/v1/launch/subscribe` and `/api/v1/contact`. Shared helpers in `src/utils/public-form.js`.
- **Rate limiting:** Subscribe limiter (8/15min/IP) and contact limiter (5/hour/IP) — verified returning 429 in smoke test.
- **Spam controls:** Honeypot fields and minimum form-fill timing (1500ms) on both endpoints — verified silent 200 + no storage in smoke/route tests.
- **Duplicate prevention:** Waitlist keyed by normalized email; duplicates update counters/timestamps without exposing subscriber data publicly.
- **Consent:** Mandatory (`CONSENT_REQUIRED`); consent timestamp + `consentIpHash` (SHA-256 prefix, not raw IP); contact IP as `ipHash`.
- **Unsubscribe:** Hashed token (SHA-256), one-click link in confirmation email; re-subscribe = fresh consent + new token + new email; replay is idempotent.
- **Admin protection:** Subscriber list/export/broadcast behind admin secret verification (`x-admin-secret`/`verifyAdminSecret`). Broadcast skips unsubscribed entries. No public subscriber/contact export.
- **Static headers (`landing/_headers`):** `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`, cache rules, immutable assets.
- **Server headers (`src/app.js`):** CSP (`default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' ...; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; ...`), HSTS (`max-age=31536000; includeSubDomains`), X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy, COOP.
- **Safe failure behavior:** Contact API stores message before best-effort mail notification; mail failure is logged server-side; UI only reports success when API accepted. Confirmation emails are best-effort (`confirmationStatus`/`notificationStatus` recorded).
- **PII handling:** No subscriber email exposed in success URLs/pages. Contact/waitlist PII stored server-side only. No auto-reply to contact submitter (avoids mail-relay abuse).
- **No public subscriber DB/export.**

## Risks / Remaining Work

- **CSP uses `'unsafe-inline'` for scripts/styles** (needed for current markup and Flutter-era compatibility). Could be tightened to nonces/hashes in a future pass; document as tradeoff.
- **HTTPS/HSTS/canonical redirects:** Enforced by Express headers for direct traffic; edge (Cloudflare/Render) should also enforce. Verify in production.
- **Dependency review:** `npm audit` not run in this pass (eslint not installed in environment either). Server dependencies include mail/network libraries; review before deployment.
- **Contact notification delivery:** Depends on configured mail provider env vars. Missing config means messages are stored but internal email alerts may not send (server logs warning/status recorded).
- **Legal/compliance claims:** Privacy/terms/cookie content should be legally reviewed for Tanzania data-protection posture; implementation does not claim certification/compliance.
- **Firestore rules:** Marketing pass did not modify mobile/backend Firestore security rules broadly.

## Environment Variables Relevant to New Behavior

- `WEBSITE_CONTACT_TO` — optional contact notification recipient (fallback `SUPPORT_EMAIL_TO`, then `support@sokovibe.co.tz`).
- Mail provider variables required by `soko_langu/server/src/services/mailer.js` (Resend/Cloudflare/SMTP paths as configured).
- `EDGE_SECRET` — for trusted `cf-connecting-ip` behind Cloudflare (rate limiter).
- `ADMIN_SECRET` — admin endpoints (must be ≥32 chars in production; boot fails if missing/placeholder).

## Deployment Security Checklist

1. Verify HTTPS and canonical `www` redirect at edge.
2. Confirm no public access to admin secrets or subscriber/contact stores.
3. Configure and test mail provider in production; verify confirmation/notification emails.
4. Monitor rate-limit/abuse logs for `/api/v1/launch/*` and `/api/v1/contact`.
5. Keep secrets in server environment variables only.
6. Re-run Lighthouse/security headers check after deploy.