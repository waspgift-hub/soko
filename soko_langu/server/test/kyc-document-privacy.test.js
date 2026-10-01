// KYC document privacy proof tests.
//
// Identity documents must be readable only by (a) the seller who submitted them
// and (b) an authenticated admin reviewer, and always through a short-lived
// presigned URL. There is no public URL for them at all.
//
// The authorization cases are exercised against the REAL Express app so the
// middleware chain under test is the one that actually ships. The resolver cases
// stub only its two I/O boundaries (the database and the R2 signer) so every
// guard can be checked without a live database or live credentials.
const { test, before, after, describe } = require('node:test');
const assert = require('node:assert');
const http = require('http');
const path = require('path');

// Must be set BEFORE config is required, otherwise `config.security.adminSecret`
// is undefined in this environment and every secret-based assertion fails for a
// reason that has nothing to do with the code under test. Value is a throwaway.
const ADMIN_SECRET = 'kyc-privacy-test-secret';
process.env.ADMIN_SECRET = ADMIN_SECRET;

// --- stubs installed before the module under test is loaded -----------------
const dbPath = require.resolve('../src/config/database');
const r2Path = require.resolve('../src/modules/media/r2-client');

const kycRow = { idImageUrl: null, selfieUrl: null, shopVideoUrl: null };
const store = {
  kycApplication: {
    async findUnique({ where }) {
      if (where.userId !== 'seller-uid-1') return null;
      return { userId: where.userId, ...kycRow };
    },
  },
};
const signerCalls = [];
require.cache[dbPath] = {
  id: dbPath, filename: dbPath, loaded: true,
  exports: { getStore: () => store },
};
require.cache[r2Path] = {
  id: r2Path, filename: r2Path, loaded: true,
  exports: {
    PRESIGNED_READ_TTL_SECONDS: 300,
    // Only ONE object exists in the fake private bucket. Keying on the exact
    // value matters: matching on the owner prefix would make a made-up uuid
    // under the same owner look like it exists.
    async objectExists({ kind, key }) {
      return kind === 'kyc'
        && key === 'kyc/user/seller-uid-1/11111111-2222-4333-8444-555555555555.jpg';
    },
    async createPresignedReadUrl({ kind, key }) {
      signerCalls.push({ kind, key });
      return { url: `https://r2.example/${kind}/${key}?sig=fake`, bucket: 'secret-bucket' };
    },
  },
};

const { isKycKey, kycKeyOwner } = require('../src/modules/media/upload-service');
const { toKycKey, presignKycDocument } = require('../src/modules/media/kyc-documents');

const SELLER_KEY = `kyc/user/seller-uid-1/11111111-2222-4333-8444-555555555555.jpg`;
kycRow.idImageUrl = SELLER_KEY;

const { app } = require('../src/app');
let server;
let port;

const ADMIN_SECRET_HEADER = { 'x-admin-secret': ADMIN_SECRET };

// The resolver tests below swap the stored document value. Restore it in a
// finally so one failing assertion cannot leave the shared fixture pointing at a
// different key and cascade into the next test.
async function withIdImage(value, fn) {
  kycRow.idImageUrl = value;
  try {
    return await fn();
  } finally {
    kycRow.idImageUrl = SELLER_KEY;
  }
}

before(async () => {
  await new Promise((resolve) => {
    server = app.listen(0, () => { port = server.address().port; resolve(); });
  });
});
after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

function req(method, urlPath, headers = {}, body) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : JSON.stringify(body);
    const r = http.request(
      {
        host: 'localhost',
        port,
        path: urlPath,
        method,
        // Content-Length must match the body actually written: declaring a
        // length and sending nothing makes express.json() wait forever.
        headers: payload
          ? { ...headers, 'Content-Length': Buffer.byteLength(payload) }
          : headers,
      },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => resolve({ status: res.statusCode, body: b }));
      },
    );
    r.on('error', reject);
    if (payload) r.write(payload);
    r.end();
  });
}

// ---------------------------------------------------------------------------
// 10. No Firebase UID enumeration can grant access to KYC.
// ---------------------------------------------------------------------------
describe('KYC key namespace cannot be forged', () => {
  test('accepts only a strict kyc/<owner>/<uuid>.<ext> key', () => {
    assert.strictEqual(isKycKey(SELLER_KEY), true);
    // Public-namespace keys are not KYC keys and must never be signed.
    assert.strictEqual(isKycKey('images/product/abc/11111111-2222-4333-8444-555555555555.jpg'), false);
    assert.strictEqual(isKycKey('kyc/../images/product/x.jpg'), false);
    assert.strictEqual(isKycKey('kyc/user/seller-uid-1/../../secret.jpg'), false);
    assert.strictEqual(isKycKey('kyc/user/seller-uid-1/not-a-uuid.jpg'), false);
    assert.strictEqual(isKycKey('kycuseruid1.jpg'), false);
    assert.strictEqual(isKycKey(''), false);
    assert.strictEqual(isKycKey(null), false);
    assert.strictEqual(isKycKey(undefined), false);
  });

  test('owner comes from the key, not from anything the caller sent', () => {
    assert.strictEqual(kycKeyOwner(SELLER_KEY), 'seller-uid-1');
    assert.strictEqual(kycKeyOwner('images/product/x/y.jpg'), null);
  });

  test('a public URL is unwrapped only when it points into the private namespace', () => {
    assert.strictEqual(
      toKycKey(`https://media.sokovibe.co.tz/${SELLER_KEY}`),
      SELLER_KEY,
      'public URL wrapping a private key should resolve to the key',
    );
    // A legacy Cloudinary URL must NOT become a servable link.
    assert.strictEqual(toKycKey('https://res.cloudinary.com/demo/image/upload/v1/x.jpg'), null);
    assert.strictEqual(toKycKey('https://media.sokovibe.co.tz/images/product/a/b.jpg'), null);
    assert.strictEqual(toKycKey(null), null);
  });
});

// ---------------------------------------------------------------------------
// 2. A normal authenticated user cannot read another user's KYC document.
// ---------------------------------------------------------------------------
describe('owner read is scoped to the verified session', () => {
  test('mismatched expected owner is refused before any database read', async () => {
    await assert.rejects(
      () => presignKycDocument({
        userId: 'someone-else-uid',
        documentId: 'idImage',
        expectOwnerUid: 'seller-uid-1',
      }),
      (e) => e.status === 403 && e.code === 'NOT_YOUR_DOCUMENT',
      'a caller must not read a document belonging to another uid',
    );
  });

  test('unknown document id is refused', async () => {
    await assert.rejects(
      () => presignKycDocument({ userId: 'seller-uid-1', documentId: 'passport-scan', expectOwnerUid: 'seller-uid-1' }),
      (e) => e.status === 400 && e.code === 'INVALID_DOCUMENT_ID',
    );
  });

  test('key owner must match the user the row was requested for', async () => {
    await withIdImage(`kyc/user/other-sellr/11111111-2222-4333-8444-555555555555.jpg`, async () => {
      await assert.rejects(
        () => presignKycDocument({ userId: 'seller-uid-1', documentId: 'idImage', expectOwnerUid: 'seller-uid-1' }),
        (e) => e.status === 403 && e.code === 'DOCUMENT_OWNER_MISMATCH',
        'a key filed under another owner must not be signed for this user',
      );
    });
  });

  test('a legacy Cloudinary row is reported, never turned into a link', async () => {
    await withIdImage('https://res.cloudinary.com/demo/image/upload/v1/legacy.jpg', async () => {
      await assert.rejects(
        () => presignKycDocument({ userId: 'seller-uid-1', documentId: 'idImage', expectOwnerUid: 'seller-uid-1' }),
        (e) => e.status === 409 && e.code === 'DOCUMENT_NOT_IN_PRIVATE_STORE',
      );
    });
  });

  test('an unknown object in the private bucket 404s instead of signing', async () => {
    await withIdImage(`kyc/user/seller-uid-1/99999999-9999-4999-8999-999999999999.jpg`, async () => {
      await assert.rejects(
        () => presignKycDocument({ userId: 'seller-uid-1', documentId: 'idImage', expectOwnerUid: 'seller-uid-1' }),
        (e) => e.status === 404 && e.code === 'DOCUMENT_NOT_FOUND',
      );
    });
  });

  test('a document field that was never submitted is a 404', async () => {
    // selfieUrl is null in the fixture.
    await assert.rejects(
      () => presignKycDocument({ userId: 'seller-uid-1', documentId: 'selfie', expectOwnerUid: 'seller-uid-1' }),
      (e) => e.status === 404 && e.code === 'DOCUMENT_NOT_SUBMITTED',
    );
  });
});

// ---------------------------------------------------------------------------
// 4. An authorized reviewer gets a temporary presigned URL and nothing else.
// ---------------------------------------------------------------------------
describe('authorized review returns a temporary URL only', () => {
  test('returns a short-lived signed URL and leaks no bucket or key material', async () => {
    const before = signerCalls.length;
    const out = await presignKycDocument({ userId: 'seller-uid-1', documentId: 'idImage' });
    assert.strictEqual(out.expiresIn, 300, 'presigned URL must be short-lived');
    assert.ok(out.url.startsWith('https://'), 'a URL is returned');
    assert.strictEqual(out.bucket, undefined, 'bucket name must not be exposed');
    assert.strictEqual(out.key, undefined, 'object key must not be exposed');
    assert.strictEqual(signerCalls.length, before + 1);
    assert.strictEqual(signerCalls.at(-1).kind, 'kyc');
    assert.strictEqual(signerCalls.at(-1).key, SELLER_KEY);
  });

  test('a user with no application is a 404, not an empty document', async () => {
    await assert.rejects(
      () => presignKycDocument({ userId: 'never-applied-uid', documentId: 'idImage' }),
      (e) => e.status === 404 && e.code === 'NO_KYC_APPLICATION',
    );
  });
});

// ---------------------------------------------------------------------------
// 1, 3, 5, 6, 9, 10 — the HTTP surface, exercised on the real app.
// ---------------------------------------------------------------------------
describe('KYC read endpoints over HTTP', () => {
  // 9. The upload-url endpoint stays protected.
  test('upload-url refuses an anonymous caller', async () => {
    const r = await req('POST', '/api/v1/media/upload-url', {
      'Content-Type': 'application/json',
    }, { kind: 'image', contentType: 'image/jpeg', ownerType: 'product', ownerId: 'seller-uid-1' });
    assert.strictEqual(r.status, 401, `expected 401, got ${r.status}`);
  });

  // A KYC upload session must never be handed out anonymously either.
  test('a KYC upload-url refuses an anonymous caller', async () => {
    const r = await req('POST', '/api/v1/media/upload-url', {
      'Content-Type': 'application/json',
    }, { kind: 'kyc', contentType: 'image/jpeg', ownerType: 'user', ownerId: 'victim-uid' });
    assert.strictEqual(r.status, 401, `expected 401, got ${r.status}`);
  });

  test('owner read-url refuses an anonymous caller', async () => {
    const r = await req('GET', '/api/v1/kyc/documents/idImage/read-url');
    assert.strictEqual(r.status, 401, `expected 401, got ${r.status}`);
  });

  test('admin read-url refuses an anonymous caller', async () => {
    const r = await req('GET', '/api/v1/admin/kyc/seller-uid-1/idImage/read-url');
    assert.strictEqual(r.status, 401, `expected 401, got ${r.status}`);
    assert.ok(!r.body.includes('http'), 'a refused request must not leak a URL');
  });

  test('admin read-url refuses a wrong admin secret', async () => {
    const r = await req('GET', '/api/v1/admin/kyc/seller-uid-1/idImage/read-url', {
      'x-admin-secret': 'wrong-secret',
    });
    assert.strictEqual(r.status, 401, `expected 401, got ${r.status}`);
  });

  test('admin read-url rejects a malformed userId even WITH a valid secret', async () => {
    const r = await req('GET', '/api/v1/admin/kyc/..%2F..%2Fetc/idImage/read-url', {
      ...ADMIN_SECRET_HEADER,
    });
    assert.ok(r.status === 400 || r.status === 404, `expected 400/404, got ${r.status}`);
  });

  test('admin read-url rejects an unknown documentId with a valid secret', async () => {
    const r = await req('GET', '/api/v1/admin/kyc/seller-uid-1/passport/read-url', {
      ...ADMIN_SECRET_HEADER,
    });
    assert.strictEqual(r.status, 400, `expected 400, got ${r.status}`);
  });

  // The gate must let an authorized reviewer THROUGH (a 404/409 from the
  // resolver proves authorization passed; 401 would mean the gate blocked it).
  test('a valid admin secret passes the review gate', async () => {
    const r = await req('GET', '/api/v1/admin/kyc/no-such-user-uid/idImage/read-url', {
      ...ADMIN_SECRET_HEADER,
    });
    assert.notStrictEqual(r.status, 401, 'valid secret must not be rejected by the gate');
    assert.notStrictEqual(r.status, 403, 'valid secret must not be rejected by the gate');
  });

  // 3. A non-admin Firebase token has role 'user' in the database and must fail.
  test('requireKycReviewer denies a non-admin role and admits an admin role', () => {
    const { requireKycReviewer } = require('../src/modules/admin/kyc-documents-routes');
    const call = (req) => {
      const res = { statusCode: 0, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
      let passed = false;
      requireKycReviewer(req, res, () => { passed = true; });
      return { passed, status: res.statusCode };
    };

    assert.strictEqual(call({ headers: {}, user: { role: 'user' } }).passed, false,
      'a normal user must not review KYC');
    assert.strictEqual(call({ headers: {}, user: { role: 'buyer' } }).passed, false);
    assert.strictEqual(call({ headers: {}, user: null }).passed, false);
    assert.strictEqual(call({ headers: {}, user: { role: 'admin' } }).passed, true,
      'a database-verified admin must pass');
    assert.strictEqual(call({ headers: {}, user: { role: 'super_admin' } }).passed, true);
    assert.strictEqual(
      call({ headers: { 'x-admin-secret': ADMIN_SECRET }, user: null }).passed, true,
      'the panel secret must pass',
    );
    assert.strictEqual(
      call({ headers: { 'x-admin-secret': 'nope' }, user: null }).passed, false,
      'a wrong secret must not pass',
    );
    // A client cannot grant itself a role: the role is read from req.user, which
    // authenticate/optionalAuth populated from the database, never from a header.
    assert.strictEqual(call({ headers: { 'x-role': 'admin' }, user: { role: 'user' } }).passed, false);
  });
});