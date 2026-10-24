// Hermetic tests for the agent orchestrator. Provider, tool registry, action
// store, permissions and audit are all stubbed so we can assert the control
// flow: high-impact tools must NOT execute until the user approves them.
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const DATABASE = require.resolve('../src/config/database');
const AGENT_TOOLS = require.resolve('../src/modules/agent/agent-tools');
const AGENT_PERMISSIONS = require.resolve('../src/modules/agent/agent-permissions');
const AGENT_ACTIONS = require.resolve('../src/modules/agent/agent-actions');
const AGENT_AUDIT = require.resolve('../src/modules/agent/agent-audit');
const AGENT_SERVICE = require.resolve('../src/modules/agent/agent-service');

const FUTURE = new Date(Date.now() + 60 * 60 * 1000).toISOString();

function toolCallTurn(name, args) {
  return {
    choices: [{
      message: {
        content: null,
        tool_calls: [{
          id: 'call_1',
          type: 'function',
          function: { name, arguments: JSON.stringify(args || {}) },
        }],
      },
    }],
  };
}

function proseTurn(content) {
  return { choices: [{ message: { content } }] };
}

function makeProvider(turns) {
  const calls = [];
  return {
    calls,
    async chat(body) {
      calls.push(body);
      const turn = turns[Math.min(calls.length - 1, turns.length - 1)];
      return { text: JSON.stringify(turn), provider: 'fake', failedOver: false };
    },
  };
}

function clearCaches() {
  for (const key of [DATABASE, AGENT_TOOLS, AGENT_PERMISSIONS, AGENT_ACTIONS, AGENT_AUDIT, AGENT_SERVICE]) {
    delete require.cache[key];
  }
}

function loadService({
  store,
  tools,
  authorize = async () => ({ allowed: true, scopes: [], requiresMfa: false }),
  actions = {},
} = {}) {
  const invoked = [];
  const created = [];
  const validated = [];
  const marks = [];
  const audit = [];

  const toolMap = tools || {};
  require.cache[DATABASE] = {
    id: DATABASE, filename: DATABASE, loaded: true,
    exports: { getStore: () => store },
  };
  require.cache[AGENT_TOOLS] = {
    id: AGENT_TOOLS, filename: AGENT_TOOLS, loaded: true,
    exports: {
      definitions: () => Object.values(toolMap).map((t) => t.definition),
      get: (name) => toolMap[name] || null,
      invoke: async (name, args) => {
        invoked.push({ name, args });
        return toolMap[name].run ? toolMap[name].run(args) : { ok: true };
      },
    },
  };
  require.cache[AGENT_PERMISSIONS] = {
    id: AGENT_PERMISSIONS, filename: AGENT_PERMISSIONS, loaded: true,
    exports: {
      authorizeTool: authorize,
      listPermissions: async () => [],
      grantPermission: async () => ({}),
      revokePermission: async () => ({}),
    },
  };
  require.cache[AGENT_ACTIONS] = {
    id: AGENT_ACTIONS, filename: AGENT_ACTIONS, loaded: true,
    exports: {
      STATUS: {
        DRAFT: 'DRAFT', AWAITING_APPROVAL: 'AWAITING_APPROVAL', APPROVED: 'APPROVED',
        EXECUTING: 'EXECUTING', SUCCEEDED: 'SUCCEEDED', FAILED: 'FAILED',
      },
      TERMINAL: new Set(['SUCCEEDED', 'FAILED', 'DENIED', 'EXPIRED', 'CANCELLED']),
      MFA_REQUIRED_TYPES: new Set(['delete_product', 'submit_withdrawal', 'confirm_delivery']),
      createPendingAction: async (opts) => {
        created.push(opts);
        return { actionId: 'act-1', status: 'DRAFT', ...opts };
      },
      validatePendingAction: async (opts) => { validated.push(opts); return opts; },
      approvePendingAction: async () => ({}),
      denyPendingAction: async () => ({}),
      cancelPendingAction: async () => ({}),
      markExecuting: async (opts) => { marks.push(['executing', opts]); return opts; },
      markSucceeded: async (opts) => { marks.push(['succeeded', opts]); return opts; },
      markFailed: async (opts) => { marks.push(['failed', opts]); return opts; },
      expirePendingAction: async () => null,
      getPendingAction: actions.getPendingAction || (async () => { throw new Error('not stubbed'); }),
      listPendingActions: async () => [],
    },
  };
  require.cache[AGENT_AUDIT] = {
    id: AGENT_AUDIT, filename: AGENT_AUDIT, loaded: true,
    exports: { log: async (entry) => { audit.push(entry); return entry; } },
  };

  delete require.cache[AGENT_SERVICE];
  const service = require(AGENT_SERVICE);
  return { service, invoked, created, validated, marks, audit };
}

function baseStore() {
  return {
    user: { findUnique: async () => ({ id: 'usr-1' }) },
    sellerProfile: { findUnique: async () => ({ id: 'sp-1' }) },
  };
}

const READ_TOOL = {
  search_products: {
    definition: { type: 'function', function: { name: 'search_products' } },
    category: 'product', impact: 'read', requiresApproval: false, requiresMfa: false,
    run: async () => ({ products: [{ id: 'p1', title: 'iPhone' }] }),
  },
};

const EXECUTE_TOOL = {
  publish_product: {
    definition: { type: 'function', function: { name: 'publish_product' } },
    category: 'product', impact: 'execute', requiresApproval: true, requiresMfa: false,
    run: async () => {
      throw new Error('publish_product must not run before approval');
    },
  },
};

beforeEach(() => clearCaches());
afterEach(() => clearCaches());

describe('agent orchestrator — approval gate', () => {
  it('proposes a compatible action instead of executing a high-impact tool', async () => {
    const provider = makeProvider([toolCallTurn('publish_product', { id: 'prod-1' })]);
    const harness = loadService({ store: baseStore(), tools: { ...EXECUTE_TOOL }, authorize: async () => ({ allowed: true, scopes: ['publish_products'], requiresMfa: false }) });

    const result = await harness.service.runTurn({
      firebaseUid: 'fb-1',
      userMessage: 'publish my iPhone listing',
      provider,
    });

    assert.equal(result.awaitingApproval, true);
    assert.equal(harness.created.length, 1);
    assert.equal(harness.created[0].actionType, 'publish_product');
    assert.equal(harness.created[0].userId, 'fb-1');
    assert.equal(harness.validated.length, 1);
    assert.equal(harness.invoked.length, 0, 'high-impact tool ran without approval');
    assert.equal(provider.calls.length, 1, 'loop should stop once an approval is pending');
  });

  it('executes a read-only tool without creating an action', async () => {
    const provider = makeProvider([toolCallTurn('search_products', { query: 'iPhone' }), proseTurn('Here are the iPhones.')]);
    const harness = loadService({ store: baseStore(), tools: { ...READ_TOOL } });

    const result = await harness.service.runTurn({
      firebaseUid: 'fb-1',
      userMessage: 'find an iPhone',
      provider,
    });

    assert.equal(result.content, 'Here are the iPhones.');
    assert.equal(harness.created.length, 0);
    assert.equal(harness.invoked.length, 1);
    assert.equal(harness.invoked[0].name, 'search_products');
  });

  it('records a denied tool and never runs it when permission is missing', async () => {
    const provider = makeProvider([toolCallTurn('delete_product', { id: 'prod-1' }), proseTurn('You are not allowed to do that.')]);
    const harness = loadService({
      store: baseStore(),
      tools: {
        delete_product: {
          definition: { type: 'function', function: { name: 'delete_product' } },
          category: 'product', impact: 'destructive', requiresApproval: true, requiresMfa: true,
          run: async () => { throw new Error('should not run'); },
        },
      },
      authorize: async () => ({ allowed: false, reason: 'Missing permission: delete_products' }),
    });

    const result = await harness.service.runTurn({
      firebaseUid: 'fb-1',
      userMessage: 'delete my listing',
      provider,
    });

    assert.equal(harness.invoked.length, 0);
    assert.equal(harness.created.length, 0);
    assert.equal(result.toolsUsed[0].status, 'denied');
  });
});

describe('agent orchestrator — execution', () => {
  it('executes an approved action and marks it succeeded', async () => {
    const harness = loadService({
      store: baseStore(),
      tools: {
        publish_product: {
          definition: { type: 'function', function: { name: 'publish_product' } },
          category: 'product', impact: 'execute', requiresApproval: true, requiresMfa: false,
          run: async () => ({ success: true, productId: 'prod-1' }),
        },
      },
      authorize: async () => ({ allowed: true, scopes: ['publish_products'] }),
      actions: {
        getPendingAction: async () => ({
          actionId: 'act-1',
          status: 'APPROVED',
          actionType: 'publish_product',
          parameters: { id: 'prod-1' },
          targetResourceId: 'prod-1',
          expiresAt: FUTURE,
        }),
      },
    });

    const result = await harness.service.executePendingAction({
      actionId: 'act-1',
      firebaseUid: 'fb-1',
    });

    assert.equal(result.status, 'SUCCEEDED');
    assert.deepEqual(result.result, { success: true, productId: 'prod-1' });
    assert.deepEqual(harness.marks.map((m) => m[0]), ['executing', 'succeeded']);
  });

  it('refuses to execute an action that is not approved', async () => {
    const harness = loadService({
      store: baseStore(),
      tools: { ...EXECUTE_TOOL },
      actions: {
        getPendingAction: async () => ({
          actionId: 'act-1',
          status: 'AWAITING_APPROVAL',
          actionType: 'publish_product',
          parameters: {},
          expiresAt: FUTURE,
        }),
      },
    });

    await assert.rejects(
      () => harness.service.executePendingAction({ actionId: 'act-1', firebaseUid: 'fb-1' }),
      (err) => err.status === 409,
    );
    assert.equal(harness.invoked.length, 0);
  });

  it('refuses to execute when the permission was revoked after approval', async () => {
    const harness = loadService({
      store: baseStore(),
      tools: {
        publish_product: {
          definition: { type: 'function', function: { name: 'publish_product' } },
          category: 'product', impact: 'execute', requiresApproval: true, requiresMfa: false,
          run: async () => ({ success: true }),
        },
      },
      authorize: async () => ({ allowed: false, reason: 'Missing permission: publish_products' }),
      actions: {
        getPendingAction: async () => ({
          actionId: 'act-1',
          status: 'APPROVED',
          actionType: 'publish_product',
          parameters: {},
          expiresAt: FUTURE,
        }),
      },
    });

    await assert.rejects(
      () => harness.service.executePendingAction({ actionId: 'act-1', firebaseUid: 'fb-1' }),
      (err) => err.status === 403,
    );
    assert.equal(harness.invoked.length, 0);
  });

  it('marks a failed action when the tool throws during execution', async () => {
    const harness = loadService({
      store: baseStore(),
      tools: {
        publish_product: {
          definition: { type: 'function', function: { name: 'publish_product' } },
          category: 'product', impact: 'execute', requiresApproval: true, requiresMfa: false,
          run: async () => { throw new Error('provider down'); },
        },
      },
      authorize: async () => ({ allowed: true, scopes: ['publish_products'] }),
      actions: {
        getPendingAction: async () => ({
          actionId: 'act-1',
          status: 'APPROVED',
          actionType: 'publish_product',
          parameters: {},
          expiresAt: FUTURE,
        }),
      },
    });

    await assert.rejects(
      () => harness.service.executePendingAction({ actionId: 'act-1', firebaseUid: 'fb-1' }),
      /provider down/,
    );
    assert.deepEqual(harness.marks.map((m) => m[0]), ['executing', 'failed']);
  });
});
