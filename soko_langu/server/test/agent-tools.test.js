// Safety invariants for the agent tool registry. These are static checks on the
// real registry: every tool that changes state must be gated behind approval,
// and every destructive/financial tool must also require MFA.
const { describe, it, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const REGISTRY = require.resolve('../src/modules/agent/agent-tools');

function loadRegistry() {
  delete require.cache[REGISTRY];
  return require(REGISTRY);
}

afterEach(() => {
  delete require.cache[REGISTRY];
});

const GATED_IMPACTS = new Set(['execute', 'destructive', 'financial']);
const MFA_IMPACTS = new Set(['destructive', 'financial']);
const VALID_IMPACTS = new Set(['read', 'prepare', 'execute', 'destructive', 'financial']);

describe('agent tool registry safety', () => {
  it('only uses known impact levels', () => {
    const { TOOLS } = loadRegistry();
    for (const [name, tool] of Object.entries(TOOLS)) {
      assert.ok(VALID_IMPACTS.has(tool.impact), `${name} has unknown impact ${tool.impact}`);
    }
  });

  it('requires explicit approval for every state-changing tool', () => {
    const { TOOLS } = loadRegistry();
    for (const [name, tool] of Object.entries(TOOLS)) {
      if (GATED_IMPACTS.has(tool.impact)) {
        assert.equal(tool.requiresApproval, true, `${name} (${tool.impact}) must require approval`);
      }
    }
  });

  it('requires MFA for destructive and financial tools', () => {
    const { TOOLS } = loadRegistry();
    for (const [name, tool] of Object.entries(TOOLS)) {
      if (MFA_IMPACTS.has(tool.impact)) {
        assert.equal(tool.requiresMfa, true, `${name} (${tool.impact}) must require MFA`);
      }
    }
  });

  it('never requires approval for read-only tools', () => {
    const { TOOLS } = loadRegistry();
    for (const [name, tool] of Object.entries(TOOLS)) {
      if (tool.impact === 'read') {
        assert.equal(tool.requiresApproval, false, `${name} is read-only but requires approval`);
        assert.equal(tool.requiresMfa, false, `${name} is read-only but requires MFA`);
      }
    }
  });

  it('gates the specific money-moving and destructive tools', () => {
    const { TOOLS } = loadRegistry();
    for (const name of ['submit_withdrawal', 'delete_product', 'confirm_delivery']) {
      assert.ok(TOOLS[name], `missing ${name}`);
      assert.equal(TOOLS[name].requiresApproval, true);
      assert.equal(TOOLS[name].requiresMfa, true);
    }
  });

  it('exposes a valid OpenAI function definition for every tool', () => {
    const { TOOLS, definitions } = loadRegistry();
    const defs = definitions();
    assert.equal(defs.length, Object.keys(TOOLS).length);
    const names = new Set();
    for (const def of defs) {
      assert.equal(def.type, 'function');
      const fn = def.function;
      assert.equal(typeof fn.name, 'string');
      assert.ok(fn.name.length > 0);
      assert.equal(typeof fn.description, 'string');
      assert.equal(fn.parameters.type, 'object');
      assert.ok(!names.has(fn.name), `duplicate tool name: ${fn.name}`);
      names.add(fn.name);
      assert.deepEqual(Object.keys(TOOLS[fn.name].definition.function), Object.keys(fn));
    }
  });

  it('maps each tool key to a definition with the same name', () => {
    const { TOOLS } = loadRegistry();
    for (const [key, tool] of Object.entries(TOOLS)) {
      assert.equal(tool.definition.function.name, key, `key ${key} != definition name`);
    }
  });

  it('returns an error object (never throws) for an unknown tool', async () => {
    const { invoke } = loadRegistry();
    const out = await invoke('transfer_all_my_money', {}, {});
    assert.match(out.error, /No such agent tool/);
  });
});
