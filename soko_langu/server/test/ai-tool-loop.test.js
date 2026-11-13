const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const GATEWAY = require.resolve('../src/modules/ai/ai-gateway');
const TOOL_LOOP = require.resolve('../src/modules/ai/tool-loop');
const REGISTRY = require.resolve('../src/modules/ai/tools/registry');
const DATABASE = require.resolve('../src/config/database');

// Every message array the loop hands to the gateway, plus the options object.
let seen = [];

/**
 * Replays a scripted provider: emits tool_calls on the first turn, then prose.
 * Returns the messages it was given on each call.
 */
function fakeGateway(script) {
  return {
    async chat(body, options) {
      seen.push({ messages: body.messages, tools: body.tools, options });
      const turn = script[Math.min(seen.length - 1, script.length - 1)];
      return { text: JSON.stringify(turn), provider: 'fake', failedOver: false };
    },
  };
}

const TOOL_CALL_TURN = {
  choices: [{ message: { content: null, tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'search_products', arguments: '{"query":"iPhone"}' } }] } }],
};
const PROSE_TURN = { choices: [{ message: { content: 'iPhone 13 is 950 000 TZS.' } }] };

function loadLoop(gateway) {
  require.cache[GATEWAY] = { id: GATEWAY, filename: GATEWAY, loaded: true, exports: { chat: gateway.chat } };
  require.cache[REGISTRY] = {
    id: REGISTRY, filename: REGISTRY, loaded: true,
    exports: {
      definitions: () => [{ type: 'function', function: { name: 'search_products' } }],
      invoke: async () => ({ ok: true, count: 1, products: [{ title: 'iPhone 13 128GB', price: 950000 }] }),
    },
  };
  require.cache[DATABASE] = {
    id: DATABASE, filename: DATABASE, loaded: true,
    exports: { getStore: () => ({ user: { findUnique: async () => null } }) },
  };
  delete require.cache[TOOL_LOOP];
  return require(TOOL_LOOP);
}

describe('chatWithTools', () => {
  let chatWithTools;

  beforeEach(() => { seen = []; chatWithTools = loadLoop(fakeGateway([TOOL_CALL_TURN, PROSE_TURN])).chatWithTools; });
  afterEach(() => {
    for (const k of [GATEWAY, TOOL_LOOP, REGISTRY, DATABASE]) delete require.cache[k];
  });

  it('never sends a role:"tool" message', async () => {
    // Gemini's OpenAI-compatible endpoint returns 400 for role:'tool' in every
    // shape tried, which made the whole failover path unusable. Folding the
    // result into a user message is the shape both providers accept.
    await chatWithTools({ model: 'm', messages: [{ role: 'user', content: 'bei ya iPhone?' }] }, null);
    for (const turn of seen) {
      const toolMsgs = turn.messages.filter((m) => m.role === 'tool');
      assert.equal(toolMsgs.length, 0, 'loop sent a role:"tool" message');
    }
  });

  it('delivers the tool result as a labelled user message', async () => {
    await chatWithTools({ model: 'm', messages: [{ role: 'user', content: 'bei ya iPhone?' }] }, null);
    const second = seen[1].messages;
    const last = second[second.length - 1];
    assert.equal(last.role, 'user');
    assert.match(last.content, /tool results/);
    assert.match(last.content, /search_products/);
    assert.match(last.content, /950000/, 'tool result payload should reach the model');
  });

  it('replays the assistant tool_calls turn so the follow-up is not orphaned', async () => {
    await chatWithTools({ model: 'm', messages: [{ role: 'user', content: 'bei ya iPhone?' }] }, null);
    const second = seen[1].messages;
    const assistant = second.find((m) => m.role === 'assistant');
    assert.ok(assistant, 'assistant turn with tool_calls was not replayed');
    assert.equal(assistant.tool_calls[0].function.name, 'search_products');
  });

  it('returns the provider envelope with sources and toolsUsed', async () => {
    const r = await chatWithTools({ model: 'm', messages: [{ role: 'user', content: 'x' }] }, null);
    const parsed = JSON.parse(r.text);
    assert.equal(parsed.choices[0].message.content, 'iPhone 13 is 950 000 TZS.');
    assert.ok(Array.isArray(parsed.sources));
    assert.deepEqual(r.toolsUsed, ['search_products']);
  });

  it('caps each provider call with the remaining loop budget', async () => {
    // The client aborts at 25s; three rounds at the 10s per-call default would
    // overrun that on their own.
    await chatWithTools({ model: 'm', messages: [{ role: 'user', content: 'x' }] }, null);
    for (const turn of seen) {
      assert.ok(Number.isFinite(turn.options.timeoutMs), 'per-call timeout not passed');
      assert.ok(turn.options.timeoutMs > 0 && turn.options.timeoutMs <= 20000, `timeout ${turn.options.timeoutMs} outside loop budget`);
    }
  });
});
