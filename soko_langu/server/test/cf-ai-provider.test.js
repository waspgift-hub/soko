const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const PROVIDER = require.resolve('../src/modules/ai/cf-ai-provider');
const GATEWAY = require.resolve('../src/modules/ai/ai-gateway');

const ENV_KEYS = ['CF_AI_URL', 'CF_AI_KEY', 'GROQ_API_KEY', 'AI_PROVIDER_ORDER'];
let savedEnv = {};
let realFetch = null;
let calls = [];

/**
 * Stand-in for the Worker. Records every request and replies with whatever
 * `respond` returns, so a test can hand back an OpenAI body, a status, or a
 * network-style throw.
 */
function fakeWorker(respond) {
  return async (url, init) => {
    calls.push({ url, init, body: parseBody(init?.body) });
    const r = respond(url, init);
    if (r instanceof Error) throw r;
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      // throwOnError only ever calls .get() on this (upstream.js parseRetryAfter),
      // so a plain object with get() is enough — and `new Map(obj)` would throw,
      // since a headers object is not iterable.
      headers: { get: (k) => (r.headers || {})[String(k).toLowerCase()] ?? null },
      text: async () => r.text,
    };
  };
}

/**
 * Groq's transcription posts a hand-built multipart Buffer, so a body is only
 * JSON sometimes. Parsing a Buffer would throw out of the stub and be reported
 * as an upstream network failure, which is a confusing way to fail a test.
 */
function parseBody(body) {
  if (typeof body !== 'string') return null;
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
}

function loadProvider() {
  delete require.cache[PROVIDER];
  return require(PROVIDER);
}

function loadGateway() {
  delete require.cache[GATEWAY];
  delete require.cache[PROVIDER];
  require.cache[PROVIDER] = { id: PROVIDER, filename: PROVIDER, loaded: true, exports: loadProvider() };
  return require(GATEWAY);
}

beforeEach(() => {
  savedEnv = {};
  for (const k of ENV_KEYS) {
    savedEnv[k] = process.env[k];
    delete process.env[k];
  }
  process.env.CF_AI_URL = 'https://soko-ai-edge.test.workers.dev';
  process.env.CF_AI_KEY = 'edge-key';
  realFetch = globalThis.fetch;
  calls = [];
});

afterEach(() => {
  globalThis.fetch = realFetch;
  for (const k of ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
  delete require.cache[PROVIDER];
  delete require.cache[GATEWAY];
});

describe('CloudflareAiProvider', () => {
  it('is unconfigured unless both the URL and the key are present', () => {
    const P = loadProvider();
    assert.equal(new P().isConfigured, true);

    delete process.env.CF_AI_KEY;
    assert.equal(new P().isConfigured, false, 'key alone is not enough');

    process.env.CF_AI_KEY = 'edge-key';
    delete process.env.CF_AI_URL;
    assert.equal(new P().isConfigured, false, 'url alone is not enough');
  });

  it('sends the shared key as X-AI-Key and returns the raw body', async () => {
    const envelope = { choices: [{ message: { content: 'karibu' } }] };
    globalThis.fetch = fakeWorker(() => ({ status: 200, text: JSON.stringify(envelope) }));

    const text = await new (loadProvider())().chat({
      model: 'openai/gpt-oss-120b',
      messages: [{ role: 'user', content: 'habari' }],
    });

    // Raw string, not a re-serialized object: groq_service.dart parses this body.
    assert.equal(typeof text, 'string');
    assert.deepEqual(JSON.parse(text), envelope);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://soko-ai-edge.test.workers.dev/chat');
    assert.equal(calls[0].init.headers['X-AI-Key'], 'edge-key');
    assert.equal(calls[0].body.model, 'openai/gpt-oss-120b', 'model id is passed through, the Worker maps it');
  });

  it('tolerates a trailing slash in CF_AI_URL', async () => {
    process.env.CF_AI_URL = 'https://soko-ai-edge.test.workers.dev/';
    globalThis.fetch = fakeWorker(() => ({ status: 200, text: '{}' }));
    await new (loadProvider())().chat({ messages: [] });
    assert.equal(calls[0].url, 'https://soko-ai-edge.test.workers.dev/chat');
  });

  it('reports the Worker status on the error so the gateway can judge failover', async () => {
    globalThis.fetch = fakeWorker(() => ({ status: 502, text: '{"error":{"message":"Workers AI error"}}' }));
    await assert.rejects(
      () => new (loadProvider())().chat({ messages: [] }),
      (err) => {
        assert.equal(err.provider, 'cloudflare');
        assert.equal(err.status, 502);
        assert.equal(err.providerMessage, 'Workers AI error');
        return true;
      }
    );
  });

  it('sends a 401 up un-failover-worthy, because a wrong key is our bug', async () => {
    globalThis.fetch = fakeWorker(() => ({ status: 401, text: '{"error":{"message":"Unauthorized"}}' }));
    const gateway = loadGateway();
    await assert.rejects(
      () => gateway.chat({ messages: [{ role: 'user', content: 'hi' }] }),
      (err) => {
        assert.equal(err.status, 401);
        assert.equal(gateway.isFailoverWorthy(err), false, 'must not be routed to another provider');
        return true;
      }
    );
  });

  it('refuses the app vision model so an image is never silently dropped', () => {
    const P = loadProvider();
    assert.equal(P.prototype.supportsModel('llama-3.2-90b-vision-preview'), false);
    assert.equal(P.prototype.supportsModel('openai/gpt-oss-120b'), true);
    assert.equal(P.prototype.supportsModel('openai/gpt-oss-20b'), true);
  });

  it('transcribes by posting base64 audio and the language', async () => {
    globalThis.fetch = fakeWorker(() => ({ status: 200, text: '{"text":"simu ya mkononi"}' }));
    const text = await new (loadProvider())().transcribe({
      audioBase64: 'QUJD',
      model: 'whisper-large-v3-turbo',
      language: 'sw',
    });
    assert.equal(JSON.parse(text).text, 'simu ya mkononi');
    assert.equal(calls[0].url, 'https://soko-ai-edge.test.workers.dev/transcribe');
    assert.deepEqual(calls[0].body, { audio: 'QUJD', language: 'sw' });
  });
});

describe('gateway with cloudflare in the chain', () => {
  it('is last in the default order', () => {
    const status = loadGateway().status().map((s) => s.name);
    assert.deepEqual(status, ['groq', 'gemini', 'cloudflare']);
  });

  it('serves from Groq without touching the Worker when Groq is healthy', async () => {
    process.env.GROQ_API_KEY = 'groq-key';
    globalThis.fetch = fakeWorker((url) =>
      url.includes('groq.com')
        ? { status: 200, text: '{"choices":[{"message":{"content":"from groq"}}]}' }
        : { status: 200, text: '{"choices":[{"message":{"content":"from cf"}}]}' }
    );
    const out = await loadGateway().chat({ messages: [{ role: 'user', content: 'hi' }] });
    assert.equal(out.provider, 'groq');
    assert.equal(calls.length, 1, 'the Worker is last, not first');
  });

  it('fails over to the Worker on a Groq 429 and reports the switch', async () => {
    process.env.GROQ_API_KEY = 'groq-key';
    globalThis.fetch = fakeWorker((url) =>
      url.includes('groq.com')
        ? { status: 429, headers: { 'retry-after': '42' }, text: '{"error":{"message":"Rate limit reached"}}' }
        : { status: 200, text: '{"choices":[{"message":{"content":"from cf"}}]}' }
    );
    const out = await loadGateway().chat({ messages: [{ role: 'user', content: 'hi' }] });
    assert.equal(out.provider, 'cloudflare');
    assert.equal(out.failedOver, true);
    assert.equal(calls.length, 2);
  });

  it('skips the Worker for a vision request instead of answering without the image', async () => {
    process.env.GROQ_API_KEY = 'groq-key';
    globalThis.fetch = fakeWorker((url) =>
      url.includes('groq.com')
        ? { status: 400, text: '{"error":{"code":"model_decommissioned","message":"model is decommissioned"}}' }
        : { status: 200, text: '{"choices":[{"message":{"content":"from cf"}}]}' }
    );
    // Groq has no vision model, so this request can only ever be served by
    // Gemini. Asserting the Worker stays out of it is the point: answering here
    // would mean replying to an image prompt with the image thrown away.
    await assert.rejects(() =>
      loadGateway().chat({ model: 'llama-3.2-90b-vision-preview', messages: [{ role: 'user', content: 'nini hii?' }] })
    );
    assert.ok(!calls.some((c) => c.url.includes('workers.dev')), 'Worker was called for a vision request');
  });

  it('fails transcription over to the Worker when Groq is rate limited', async () => {
    process.env.GROQ_API_KEY = 'groq-key';
    globalThis.fetch = fakeWorker((url) =>
      url.includes('groq.com')
        ? { status: 429, text: '{"error":{"message":"Rate limit reached"}}' }
        : { status: 200, text: '{"text":"nini kwenye picha"}' }
    );
    const text = await loadGateway().transcribe({ audioBase64: 'QUJD', language: 'sw' });
    assert.equal(JSON.parse(text).text, 'nini kwenye picha');
    assert.equal(calls.length, 2);
  });

  it('reports no transcription provider when the Worker is unconfigured and Groq is absent', async () => {
    delete process.env.CF_AI_URL;
    delete process.env.CF_AI_KEY;
    globalThis.fetch = fakeWorker(() => ({ status: 200, text: '{}' }));
    await assert.rejects(
      () => loadGateway().transcribe({ audioBase64: 'QUJD', language: 'sw' }),
      (err) => {
        assert.equal(err.code, 'AI_NO_PROVIDER');
        return true;
      }
    );
    assert.equal(calls.length, 0, 'an unconfigured provider must not be called');
  });
});
