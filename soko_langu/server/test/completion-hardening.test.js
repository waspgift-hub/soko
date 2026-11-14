// Regression tests for the production-hardening pass.
//
// Each case pins a decision that was previously inconsistent or unenforced:
//   * payment providers the factory cannot serve must fail as a typed 400
//   * the approved 3.5% commission is the default and both units are accepted
//   * dispatch writes the same 14-day auto-release deadline the sweep uses
//   * trial subscriptions use the canonical `trialing` status
//   * OTP delivery falls back to SMS
//   * the Company router is actually mounted and protected
//   * admin RBAC denies a role outside a permission's domain
//   * staff session tokens authenticate and expire
const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');

// Config is read from env at require time; make the commission default
// assertion independent of the host shell.
delete process.env.PLATFORM_COMMISSION_PERCENT;

const http = require('http');

describe('payment provider validation', () => {
  test('an unimplemented provider is a typed 400, never a 500', async () => {
    const { initiatePayment } = require('../src/modules/payments/payment-service');
    await assert.rejects(
      () => initiatePayment({
        orderId: 'order-1',
        buyerId: 'buyer-1',
        provider: 'card',
        amount: 1000,
        phoneNumber: '+255700000000',
      }),
      (err) => err.status === 400 && err.message === 'UNSUPPORTED_PAYMENT_PROVIDER',
    );
  });

  test('the same rejection applies to bank', async () => {
    const { initiatePayment } = require('../src/modules/payments/payment-service');
    await assert.rejects(
      () => initiatePayment({
        orderId: 'order-1',
        buyerId: 'buyer-1',
        provider: 'bank',
        amount: 1000,
        phoneNumber: '+255700000000',
      }),
      /UNSUPPORTED_PAYMENT_PROVIDER/,
    );
  });
});

describe('commission policy', () => {
  const settings = require('../src/modules/admin/settings-service');
  const config = require('../src/config');

  test('fresh install defaults to the approved 3.5% commission', () => {
    assert.equal(config.business.platformCommissionPercent, 0.035);
    assert.equal(settings.DEFAULTS.paymentsAndCurrency.platformCommissionPct, 3.5);
    assert.equal(settings.commissionPercent({ paymentsAndCurrency: { platformCommissionPct: 3.5 } }), 0.035);
  });

  test('both percentage and fraction units are accepted, junk is zero', () => {
    assert.equal(settings.commissionPercent({ paymentsAndCurrency: { platformCommissionPct: 0.035 } }), 0.035);
    assert.equal(settings.commissionPercent({ paymentsAndCurrency: { platformCommissionPct: 0 } }), 0);
    assert.equal(settings.commissionPercent({ paymentsAndCurrency: { platformCommissionPct: 100 } }), 1);
    assert.equal(settings.commissionPercent({ paymentsAndCurrency: { platformCommissionPct: 101 } }), 0);
    assert.equal(settings.commissionPercent({}), 0);
  });

  test('fresh install is AzamPay-first with a 14-day escrow window', () => {
    const p = settings.DEFAULTS.paymentsAndCurrency;
    assert.equal(p.primaryGateway, 'azampay');
    assert.equal(p.gateways.azamPay.enabled, true);
    assert.equal(p.gateways.clickpesa.enabled, false);
    assert.equal(p.escrowReleaseDays, 14);
  });
});

describe('escrow deadline', () => {
  test('dispatch writes the same 14-day window the finance sweep uses', async () => {
    const config = require('../src/config');
    const { dispatchOrder } = require('../src/services/escrow-service');

    let patch = null;
    const db = {
      collection: () => ({
        doc: () => ({
          async get() {
            return {
              exists: true,
              data: () => ({ sellerId: 'seller-1', status: 'IN_ESCROW', amount: 1000 }),
              ref: { update: async (p) => { patch = p; } },
            };
          },
        }),
      }),
    };

    const before = Date.now();
    await dispatchOrder({ orderId: 'o1', sellerId: 'seller-1', courierDetails: {}, db });

    assert.ok(patch, 'dispatch must write an update');
    assert.equal(patch.status, 'DISPATCHED');
    const windowDays = (patch.autoReleaseDeadline.getTime() - before) / (24 * 60 * 60 * 1000);
    assert.ok(
      Math.abs(windowDays - config.finance.autoReleaseDays) < 0.01,
      `deadline must be ${config.finance.autoReleaseDays} days, got ${windowDays}`,
    );
  });
});

describe('subscription status', () => {
  const { VALID_TRANSITIONS } = require('../src/modules/subscriptions/plans');

  test('trial uses the canonical trialing status', () => {
    assert.ok(VALID_TRANSITIONS.inactive.includes('trialing'));
    assert.deepEqual(VALID_TRANSITIONS.trialing, ['active', 'expired', 'pending_payment']);
    assert.equal(VALID_TRANSITIONS.trailing, undefined);
  });

  test('trial rows in the legacy misspelling cannot silently pass', () => {
    for (const targets of Object.values(VALID_TRANSITIONS)) {
      assert.ok(!targets.includes('trailing'));
    }
  });
});

describe('OTP channel order', () => {
  test('default chain includes SMS as a fallback', () => {
    delete process.env.OTP_CHANNEL_ORDER;
    const { channelsFromEnv } = require('../src/services/otp-delivery');
    assert.deepEqual(channelsFromEnv(), ['push', 'whatsapp', 'sms']);
  });

  test('an explicit order is still honoured', () => {
    process.env.OTP_CHANNEL_ORDER = 'sms,whatsapp';
    const { channelsFromEnv } = require('../src/services/otp-delivery');
    assert.deepEqual(channelsFromEnv(), ['sms', 'whatsapp']);
    delete process.env.OTP_CHANNEL_ORDER;
  });
});

describe('admin RBAC', () => {
  const { can, requireAdminPermission } = require('../src/middleware/admin-rbac');

  function fakeRes() {
    return {
      statusCode: 200,
      body: null,
      status(code) { this.statusCode = code; return this; },
      json(payload) { this.body = payload; return this; },
    };
  }

  test('support cannot touch finance, finance can', () => {
    assert.equal(can({ adminStaff: { role: 'support', permissions: ['users:read'] } }, 'finance:write'), false);
    assert.equal(can({ adminStaff: { role: 'finance', permissions: ['finance:read', 'finance:write'] } }, 'finance:write'), true);
  });

  test('the shared secret maps to super_admin (wildcard)', () => {
    assert.equal(can({ isAdmin: true }, 'settings:write'), true);
  });

  test('domain wildcards from the staff editor are honoured', () => {
    assert.equal(can({ adminStaff: { role: 'admin', permissions: ['finance:*'] } }, 'finance:write'), true);
    assert.equal(can({ adminStaff: { role: 'admin', permissions: ['finance:*'] } }, 'users:write'), false);
  });

  test('guard returns 401 unauthenticated and 403 outside the permission', () => {
    const unauth = fakeRes();
    let called = false;
    requireAdminPermission('finance:write')({}, unauth, () => { called = true; });
    assert.equal(unauth.statusCode, 401);
    assert.equal(called, false);

    const denied = fakeRes();
    requireAdminPermission('finance:write')(
      { adminStaff: { role: 'support', permissions: ['users:read'] } },
      denied,
      () => { called = true; },
    );
    assert.equal(denied.statusCode, 403);
    assert.equal(denied.body.error, 'ADMIN_PERMISSION_REQUIRED');
  });
});

describe('staff session authentication', () => {
  const commerceStore = require('../src/services/commerce-store');
  const { authenticateAdmin } = require('../src/middleware/auth');
  const originalGetDocument = commerceStore.getDocument;

  function fakeRes() {
    return {
      statusCode: 200,
      body: null,
      status(code) { this.statusCode = code; return this; },
      json(payload) { this.body = payload; return this; },
    };
  }

  const activeStaff = {
    id: 'staff_1',
    email: 'finance@sokovibe.co.tz',
    name: 'Finance',
    role: 'finance',
    active: true,
    permissions: ['finance:read', 'finance:write'],
  };

  before(() => {
    commerceStore.getDocument = async (collection, id) => {
      if (collection === 'staff_sessions' && id === 'a'.repeat(48)) {
        return { staffId: 'staff_1', role: 'finance', expiresAtMs: Date.now() + 60_000 };
      }
      if (collection === 'admin_staff' && id === 'staff_1') return activeStaff;
      return null;
    };
  });

  after(() => {
    commerceStore.getDocument = originalGetDocument;
  });

  test('a valid staff token is accepted and carries its permissions', async () => {
    const req = { headers: { 'x-staff-token': 'a'.repeat(48) } };
    const res = fakeRes();
    let next = false;
    await authenticateAdmin(req, res, () => { next = true; });
    assert.equal(next, true);
    assert.equal(req.isAdmin, true);
    assert.equal(req.adminStaff.id, 'staff_1');
    assert.deepEqual(req.adminStaff.permissions, ['finance:read', 'finance:write']);
  });

  test('an expired session is rejected', async () => {
    const session = { staffId: 'staff_1', expiresAtMs: Date.now() - 1 };
    commerceStore.getDocument = async (collection) => (collection === 'staff_sessions' ? session : activeStaff);
    const req = { headers: { 'x-staff-token': 'b'.repeat(48) } };
    const res = fakeRes();
    await authenticateAdmin(req, res, () => {});
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.error, 'STAFF_SESSION_EXPIRED');
    commerceStore.getDocument = async (collection, id) => {
      if (collection === 'staff_sessions' && id === 'a'.repeat(48)) {
        return { staffId: 'staff_1', role: 'finance', expiresAtMs: Date.now() + 60_000 };
      }
      if (collection === 'admin_staff' && id === 'staff_1') return activeStaff;
      return null;
    };
  });

  test('a deactivated staff member is rejected', async () => {
    commerceStore.getDocument = async (collection) => {
      if (collection === 'staff_sessions') {
        return { staffId: 'staff_1', expiresAtMs: Date.now() + 60_000 };
      }
      return { ...activeStaff, active: false };
    };
    const req = { headers: { 'x-staff-token': 'c'.repeat(48) } };
    const res = fakeRes();
    await authenticateAdmin(req, res, () => {});
    assert.equal(res.statusCode, 403);
    assert.equal(res.body.error, 'STAFF_INACTIVE');
    commerceStore.getDocument = async (collection, id) => {
      if (collection === 'staff_sessions' && id === 'a'.repeat(48)) {
        return { staffId: 'staff_1', role: 'finance', expiresAtMs: Date.now() + 60_000 };
      }
      if (collection === 'admin_staff' && id === 'staff_1') return activeStaff;
      return null;
    };
  });
});

describe('company router mount', () => {
  let server;
  let port;

  before(async () => {
    const { app } = require('../src/app');
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', () => {
        port = server.address().port;
        resolve();
      });
    });
  });

  after(async () => {
    if (server) await new Promise((resolve) => server.close(resolve));
  });

  test('company routes are reachable and require auth', async () => {
    const status = await new Promise((resolve, reject) => {
      const req = http.request(
        { host: '127.0.0.1', port, path: '/api/v1/company/me', method: 'GET' },
        (res) => {
          res.resume();
          res.on('end', () => resolve(res.statusCode));
        },
      );
      req.on('error', reject);
      req.end();
    });
    assert.equal(status, 401);
  });
});
