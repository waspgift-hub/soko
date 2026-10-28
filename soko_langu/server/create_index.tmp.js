// One-shot: create the missing categories composite index on the live project.
// Firestore has no Admin SDK for indexes (console/gcloud only), so this calls
// the Firestore REST API with a self-signed JWT from the service account.
require('dotenv').config();
const crypto = require('crypto');
const https = require('https');

const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!raw) { console.log('NO_SERVICE_ACCOUNT_JSON'); process.exit(1); }
const sa = JSON.parse(raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8'));

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function request(method, url, body, token) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = 'Bearer ' + token;
    const data = body ? JSON.stringify(body) : null;
    const req = https.request(
      { method, hostname: u.hostname, path: u.pathname + u.search, headers, timeout: 30000 },
      (res) => {
        let out = '';
        res.on('data', (c) => (out += c));
        res.on('end', () => resolve({ status: res.statusCode, body: out }));
      }
    );
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    if (data) req.write(data);
    req.end();
  });
}

(async () => {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/cloud-platform',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })
  );
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(header + '.' + claims);
  const assertion = header + '.' + claims + '.' + b64url(signer.sign(sa.private_key));

  const tok = await request('POST', 'https://oauth2.googleapis.com/token', {
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  if (tok.status !== 200) { console.log('TOKEN FAILED', tok.status, tok.body.slice(0, 300)); process.exit(1); }
  const token = JSON.parse(tok.body).access_token;
  console.log('token acquired');

  const project = sa.project_id;
  const url =
    'https://firestore.googleapis.com/v1/projects/' + project +
    '/databases/(default)/collectionGroups/categories/indexes';
  const body = {
    fields: [
      { fieldPath: 'isActive', order: 'ASCENDING' },
      { fieldPath: 'sortOrder', order: 'ASCENDING' },
    ],
    queryScope: 'COLLECTION',
  };
  const res = await request('POST', url, body, token);
  console.log('create status =', res.status);
  console.log(res.body.slice(0, 600));
})();
