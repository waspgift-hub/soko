// Hermetic tests for the agent permission system and pending-action lifecycle.
// The Firestore store is replaced with an in-memory implementation so the real
// modules run their safety rules (scoping, expiration, ownership, transitions)
// without any network or credentials.
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const DATABASE = require.resolve('../src/config/database');
const AGENT_TOOLS = require.resolve('../src/modules/agent/agent-tools');
const PERMISSIONS = require.resolve('../src/modules/agent/agent-permissions');
const ACTIONS = require.resolve('../src/modules/agent/agent-actions');
const PRODUCT_SERVICE = require.resolve('../src/modules/products/product-service');

/*──────────────────────── In-memory Firestore-shaped store ────────────────────────*/

function createStore(seed = {}) {
  const collections = new Map();

  function mapFor(name) {
    if (!collections.has(name)) collections.set(name, new Map());
    return collections.get(name);
  }

  for (const [name, docs] of Object.entries(seed)) {
    for (const [id, doc] of Object.entries(docs)) mapFor(name).set(id, { ...doc });
  }

  function docRef(name, id) {
    return {
      id,
      async set(doc) {
        mapFor(name).set(id, { ...doc });
      },
      async get() {
        const exists = mapFor(name).has(id);
        const stored = mapFor(name).get(id);
        return { exists, id, data: () => (stored ? { ...stored } : undefined) };
      },
      async update(updates) {
        const stored = mapFor(name).get(id);
        if (!stored) throw new Error(`document not found: ${name}/${id}`);
        Object.assign(stored, updates);
      },
    };
  }

  function makeQuery(name, filters = [], order = null, max = null) {
    return {
      where(field, op, value) {
        return makeQuery(name, [...filters, [field, op, value]], order, max);
      },
      orderBy(field, dir = 'asc') {
        return makeQuery(name, filters, [field, dir], max);
      },
      limit(n) {
        return makeQuery(name, filters, order, n);
      },
      async get() {
        let rows = [...mapFor(name).entries()].map(([id, doc]) => ({ id, doc }));
        rows = rows.filter(({ doc }) => filters.every(([f, op, v]) => op === '==' && doc[f] === v));
        if (order) {
          const [field, dir] = order;
          rows.sort((a, b) => {
            const av = a.doc[field];
            const bv = b.doc[field];
            if (av === bv) return 0;
            const cmp = av < bv ? -1 : 1;
            return dir === 'desc' ? -cmp : cmp;
          });
        }
        if (max != null) rows = rows.slice(0, max);
        const docs = rows.map(({ id, doc }) => ({
          id,
          ref: docRef(name, id),
          data: () => ({ ...doc }),
        }));
        return { docs, empty: docs.length === 0, size: docs.length };
      },
    };
  }

  const batch = [];
  return {
    collection(name) {
      const q = makeQuery(name);
      return Object.assign(q, { doc: (id) => docRef(name, id) });
    },
    batch() {
      return {
        update(ref, updates) {
          batch.push({ ref, updates });
        },
        async commit() {
          for (const op of batch.splice(0)) await op.ref.update(op.updates);
        },
      };
    },
    user: { findUnique: async () => null },
    sellerProfile: { findUnique: async () => null },
  };
}

function clearCaches() {
  for (const key of [DATABASE, AGENT_TOOLS, PERMISSIONS, ACTIONS, PRODUCT_SERVICE]) {
    delete require.cache[key];
  }
}

function loadPermissions(store, tools = {}) {
  require.cache[DATABASE] = {
    id: DATABASE, filename: DATABASE, loaded: true,
    exports: { getStore: () => store },
  };
  require.cache[AGENT_TOOLS] = {
    id: AGENT_TOOLS, filename: AGENT_TOOLS, loaded: true,
    exports: { get: (name) => tools[name] || null },
  };
  delete require.cache[PERMISSIONS];
  return require(PERMISSIONS);
}

function loadActions(store, { productService } = {}) {
  require.cache[DATABASE] = {
    id: DATABASE, filename: DATABASE, loaded: true,
    exports: { getStore: () => store },
  };
  if (productService) {
    require.cache[PRODUCT_SERVICE] = {
      id: PRODUCT_SERVICE, filename: PRODUCT_SERVICE, loaded: true,
      exports: productService,
    };
  }
  delete require.cache[PERMISSIONS];
  delete require.cache[ACTIONS];
  return require(ACTIONS);
}

async function seedPermission(store, { id, userId, scope, expiresAt }) {
  await store.collection('agent_permissions').doc(id).set({
    permissionId: id,
    userId,
    scope,
    status: 'granted',
    expiresAt: expiresAt || new Date(Date.now() + 60 * 60 * 1000).toISOString(),
  });
}

/*──────────────────────── Permissions ────────────────────────*/

describe('agent permissions', () => {
  let store;
  let permissions;

  beforeEach(() => {
    const toolSpecs = {
      search_products: { requiresMfa: false },
      delete_product: { requiresMfa: true },
      submit_withdrawal: { requiresMfa: true },
      publish_product: { requiresMfa: false },
    };
    store = createStore();
    permissions = loadPermissions(store, toolSpecs);
  });

  afterEach(clearCaches);

  it('rejects an unknown scope', async () => {
    await assert.rejects(
      () => permissions.grantPermission({ userId: 'u1', scope: 'root_everything' }),
      /Unknown permission scope/,
    );
  });

  it('grants a scope and then allows it', async () => {
    const granted = await permissions.grantPermission({ userId: 'u1', scope: 'read_my_profile' });
    assert.equal(granted.status, 'granted');
    const check = await permissions.checkPermission({ userId: 'u1', scope: 'read_my_profile' });
    assert.equal(check.allowed, true);
  });

  it('does not leak a permission to another user', async () => {
    await permissions.grantPermission({ userId: 'u1', scope: 'read_my_profile' });
    const check = await permissions.checkPermission({ userId: 'u2', scope: 'read_my_profile' });
    assert.equal(check.allowed, false);
  });

  it('revokes every active grant of a scope', async () => {
    await permissions.grantPermission({ userId: 'u1', scope: 'publish_products' });
    await permissions.grantPermission({ userId: 'u1', scope: 'publish_products' });
    const result = await permissions.revokePermission({ userId: 'u1', scope: 'publish_products' });
    assert.equal(result.revoked, 2);
    const check = await permissions.checkPermission({ userId: 'u1', scope: 'publish_products' });
    assert.equal(check.allowed, false);
  });

  it('treats an expired grant as not allowed', async () => {
    await seedPermission(store, {
      id: 'p-expired', userId: 'u1', scope: 'read_my_wallet',
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const check = await permissions.checkPermission({ userId: 'u1', scope: 'read_my_wallet' });
    assert.equal(check.allowed, false);
  });

  it('maps tools to scopes, with public tools unmapped', () => {
    assert.deepEqual(permissions.requiredScopesForTool('delete_product'), ['delete_products']);
    assert.deepEqual(permissions.requiredScopesForTool('submit_withdrawal'), ['execute_withdrawal']);
    assert.equal(permissions.requiredScopesForTool('search_products'), null);
  });

  it('denies a tool until its scope is granted, then allows it', async () => {
    const before = await permissions.authorizeTool({ userId: 'u1', toolName: 'delete_product' });
    assert.equal(before.allowed, false);

    await permissions.grantPermission({ userId: 'u1', scope: 'delete_products' });
    const after = await permissions.authorizeTool({ userId: 'u1', toolName: 'delete_product' });
    assert.equal(after.allowed, true);
    assert.equal(after.requiresMfa, true);
  });

  it('always allows a public tool that needs no permission', async () => {
    const result = await permissions.authorizeTool({ userId: 'u1', toolName: 'search_products' });
    assert.equal(result.allowed, true);
  });

  it('refuses an unknown tool', async () => {
    const result = await permissions.authorizeTool({ userId: 'u1', toolName: 'pay_someone' });
    assert.equal(result.allowed, false);
  });

  it('applies shorter TTLs to financial scopes than to read scopes', () => {
    assert.ok(
      permissions.scopeTtlMs('execute_withdrawal') < permissions.scopeTtlMs('read_my_profile'),
      'withdrawal grants should expire before long-lived read grants',
    );
  });
});

/*──────────────────────── Pending actions ────────────────────────*/

describe('agent pending actions', () => {
  let store;
  let actions;

  async function createAwaiting(overrides = {}) {
    const created = await actions.createPendingAction({
      userId: 'u1',
      actionType: 'submit_withdrawal',
      targetResourceType: 'wallet',
      parameters: { amount: 5000, phoneNumber: '255700000000' },
      requiredPermissions: ['execute_withdrawal'],
      requiredMfa: true,
      ...overrides,
    });
    await actions.validatePendingAction({ actionId: created.actionId, userId: 'u1' });
    return created;
  }

  beforeEach(async () => {
    store = createStore();
    actions = loadActions(store);
    await seedPermission(store, { id: 'p-exec', userId: 'u1', scope: 'execute_withdrawal' });
    await seedPermission(store, { id: 'p-manage', userId: 'u1', scope: 'manage_my_orders' });
    await seedPermission(store, { id: 'p-del', userId: 'u1', scope: 'delete_products' });
    await seedPermission(store, { id: 'p-pub', userId: 'u1', scope: 'publish_products' });
  });

  afterEach(clearCaches);

  it('creates a DRAFT action bound to the requesting user', async () => {
    const action = await actions.createPendingAction({
      userId: 'u1',
      actionType: 'delete_product',
      targetResourceType: 'product',
      targetResourceId: 'prod-1',
      parameters: { id: 'prod-1' },
      requiredPermissions: ['delete_products'],
      requiredMfa: true,
    });
    assert.equal(action.status, actions.STATUS.DRAFT);
    assert.equal(action.userId, 'u1');
    assert.equal(action.actionType, 'delete_product');
    assert.equal(action.requiredMfa, true);
    assert.ok(action.expiresAt, 'an expiry must be set');
  });

  it('advances a validated action to AWAITING_APPROVAL', async () => {
    const action = await createAwaiting();
    const stored = await actions.getPendingAction({ actionId: action.actionId, userId: 'u1' });
    assert.equal(stored.status, actions.STATUS.AWAITING_APPROVAL);
  });

  it('refuses to validate when the permission was revoked', async () => {
    const created = await actions.createPendingAction({
      userId: 'u1',
      actionType: 'submit_withdrawal',
      targetResourceType: 'wallet',
      parameters: { amount: 5000 },
      requiredPermissions: ['execute_withdrawal'],
      requiredMfa: true,
    });
    await store.collection('agent_permissions').doc('p-exec').update({ status: 'revoked' });
    await assert.rejects(
      () => actions.validatePendingAction({ actionId: created.actionId, userId: 'u1' }),
      /Permission not held/,
    );
    const stored = await actions.getPendingAction({ actionId: created.actionId, userId: 'u1' });
    assert.equal(stored.status, actions.STATUS.FAILED);
  });

  it('hides an action belonging to another user', async () => {
    const action = await createAwaiting();
    await assert.rejects(
      () => actions.getPendingAction({ actionId: action.actionId, userId: 'u2' }),
      (err) => err.status === 404,
    );
  });

  it('approves an action awaiting approval', async () => {
    const action = await createAwaiting();
    const approved = await actions.approvePendingAction({ actionId: action.actionId, userId: 'u1' });
    assert.equal(approved.status, actions.STATUS.APPROVED);
    assert.ok(approved.approvedAt);
  });

  it('cannot approve a draft that was never validated', async () => {
    const created = await actions.createPendingAction({
      userId: 'u1',
      actionType: 'submit_withdrawal',
      targetResourceType: 'wallet',
      parameters: { amount: 5000 },
      requiredPermissions: ['execute_withdrawal'],
      requiredMfa: true,
    });
    await assert.rejects(
      () => actions.approvePendingAction({ actionId: created.actionId, userId: 'u1' }),
      (err) => err.status === 409,
    );
  });

  it('denies an action awaiting approval', async () => {
    const action = await createAwaiting();
    const denied = await actions.denyPendingAction({ actionId: action.actionId, userId: 'u1', reason: 'not now' });
    assert.equal(denied.status, actions.STATUS.DENIED);
    assert.equal(denied.error, 'not now');
  });

  it('cancels an action awaiting approval', async () => {
    const action = await createAwaiting();
    const cancelled = await actions.cancelPendingAction({ actionId: action.actionId, userId: 'u1' });
    assert.equal(cancelled.status, actions.STATUS.CANCELLED);
  });

  it('refuses to execute an action that is only awaiting approval', async () => {
    const action = await createAwaiting();
    await assert.rejects(
      () => actions.markExecuting({ actionId: action.actionId, userId: 'u1' }),
      (err) => err.status === 409,
    );
  });

  it('runs the approved -> executing -> succeeded path', async () => {
    const action = await createAwaiting();
    await actions.approvePendingAction({ actionId: action.actionId, userId: 'u1' });

    const executing = await actions.markExecuting({ actionId: action.actionId, userId: 'u1' });
    assert.equal(executing.status, actions.STATUS.EXECUTING);
    assert.equal(executing.attempts, 1);

    const succeeded = await actions.markSucceeded({
      actionId: action.actionId,
      userId: 'u1',
      result: { ok: true },
    });
    assert.equal(succeeded.status, actions.STATUS.SUCCEEDED);
    assert.deepEqual(succeeded.result, { ok: true });
  });

  it('expires a stale action on approval attempt', async () => {
    const stale = await actions.createPendingAction({
      userId: 'u1',
      actionType: 'submit_withdrawal',
      targetResourceType: 'wallet',
      parameters: { amount: 5000 },
      requiredPermissions: ['execute_withdrawal'],
      requiredMfa: true,
      ttlMs: -1000,
    });
    await actions.validatePendingAction({ actionId: stale.actionId, userId: 'u1' });

    await assert.rejects(
      () => actions.approvePendingAction({ actionId: stale.actionId, userId: 'u1' }),
      (err) => err.status === 410,
    );
    const stored = await actions.getPendingAction({ actionId: stale.actionId, userId: 'u1' });
    assert.equal(stored.status, actions.STATUS.EXPIRED);
  });

  it('lists only the caller’s actions', async () => {
    await createAwaiting();
    const mine = await actions.listPendingActions({ userId: 'u1' });
    const theirs = await actions.listPendingActions({ userId: 'u2' });
    assert.equal(mine.length, 1);
    assert.equal(theirs.length, 0);
  });

  it('marks MFA-required action types', () => {
    for (const type of ['delete_product', 'submit_withdrawal', 'confirm_delivery']) {
      assert.ok(actions.MFA_REQUIRED_TYPES.has(type), `${type} should require MFA`);
    }
  });

  it('enforces the transition table', () => {
    assert.equal(actions.isValidTransition('DRAFT', 'AWAITING_APPROVAL'), true);
    assert.equal(actions.isValidTransition('AWAITING_APPROVAL', 'APPROVED'), true);
    assert.equal(actions.isValidTransition('SUCCEEDED', 'EXECUTING'), false);
    assert.equal(actions.isValidTransition('DENIED', 'APPROVED'), false);
  });

  it('rejects approval when a product resource is no longer accessible', async () => {
    const productStore = createStore();
    productStore.user.findUnique = async () => ({ id: 'usr-1' });
    productStore.sellerProfile.findUnique = async () => ({ id: 'sp-1' });
    const guarded = loadActions(productStore, {
      productService: {
        getOwnedProduct: async () => {
          const err = new Error('gone');
          err.status = 404;
          throw err;
        },
      },
    });
    await seedPermission(productStore, { id: 'p-pub', userId: 'u1', scope: 'publish_products' });

    const created = await guarded.createPendingAction({
      userId: 'u1',
      actionType: 'publish_product',
      targetResourceType: 'product',
      targetResourceId: 'prod-1',
      parameters: { id: 'prod-1' },
      requiredPermissions: ['publish_products'],
      requiredMfa: false,
    });

    await assert.rejects(
      () => guarded.validatePendingAction({ actionId: created.actionId, userId: 'u1' }),
      (err) => err.status === 409,
    );
  });
});
