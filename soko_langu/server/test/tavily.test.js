const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');

const TAVILY = require.resolve('../src/modules/ai/tavily');
const { searchWeb } = require('../src/modules/ai/tavily');

/**
 * Builds a Tavily response the way the real API was measured to shape it.
 * Defaults are a genuinely responsive result; tests override the one field they
 * are exercising so each failure mode is isolated.
 */
function tavilyResponse(overrides = {}) {
  const body = {
    query: 'test',
    answer: 'a summary from tavily',
    results: [
      {
        title: '1 USD to TZS Exchange Rate: 1 USD = 2,638.00 TZS',
        url: 'https://www.xe.com/en-us/currencyconverter/usd-tzs',
        content: 'Convert 1 USD to TZS. The exchange rate today is 2638 Tanzanian Shillings per dollar.',
        score: 0.95,
      },
    ],
    ...overrides,
  };
  return {
    ok: true,
    status: 200,
    async json() {
      return body;
    },
    async text() {
      return JSON.stringify(body);
    },
  };
}

let calls = [];
let key = 'test-key';
let originalKey;
let originalFetch;

beforeEach(() => {
  calls = [];
  key = 'test-key';
  process.env.TAVILY_API_KEY = key;
  originalFetch = global.fetch;
  originalKey = process.env.TAVILY_API_KEY;
  global.fetch = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return tavilyResponse();
  };
});

afterEach(() => {
  global.fetch = originalFetch;
  if (originalKey === undefined) delete process.env.TAVILY_API_KEY;
  else process.env.TAVILY_API_KEY = originalKey;
});

describe('searchWeb input handling', () => {
  it('returns nothing rather than searching for an empty query', async () => {
    for (const q of [undefined, null, '', '   ']) {
      const out = await searchWeb({ query: q });
      assert.equal(out.sources.length, 0, `expected no sources for ${JSON.stringify(q)}`);
    }
    assert.equal(calls.length, 0, 'must not spend a search on an empty query');
  });

  it('degrades to an explanation instead of inventing when the key is absent', async () => {
    delete process.env.TAVILY_API_KEY;
    const out = await searchWeb({ query: 'usd to tzs' });
    assert.equal(out.sources.length, 0);
    // The model needs wording it can pass on to the user, not a raw failure.
    assert.match(out.note, /not configured/i);
    assert.equal(out.error, undefined, 'a missing key is configuration, not a request failure');
  });
});

describe('searchWeb request shape', () => {
  it('posts the query and key, and caps depth and result count', async () => {
    await searchWeb({ query: '  usd to tzs  ', maxResults: 99 });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://api.tavily.com/search');
    assert.equal(calls[0].init.method, 'POST');
    assert.equal(calls[0].body.query, 'usd to tzs', 'query must be trimmed');
    assert.equal(calls[0].body.api_key, key);
    assert.equal(calls[0].body.search_depth, 'basic');
    assert.ok(calls[0].body.max_results <= 5, 'max_results must be clamped');
  });

  it('sends a timeout signal so a hung search cannot outlive the loop budget', async () => {
    await searchWeb({ query: 'usd to tzs' });
    assert.ok(calls[0].init.signal, 'an AbortSignal is required');
  });
});

describe('searchWeb relevance gating', () => {
  it('cites a responsive result', async () => {
    const out = await searchWeb({ query: '1 usd to tzs exchange rate' });
    assert.equal(out.sources.length, 1);
    assert.equal(out.sources[0].url, 'https://www.xe.com/en-us/currencyconverter/usd-tzs');
    assert.match(out.sources[0].ref, /^web-\d+$/);
  });

  it('withholds a low-scoring result so the model cannot cite it', async () => {
    global.fetch = async () => tavilyResponse({ results: [{ title: 'loosely related', url: 'https://example.com/tzs', content: 'usd to tzs exchange rate', score: 0.3 }] });
    const out = await searchWeb({ query: '1 usd to tzs exchange rate' });
    assert.equal(out.sources.length, 0, 'a 0.3 result must be withheld');
    assert.match(out.note, /nothing relevant/i);
  });

  it('withholds an on-topic result that never states the asked-for detail', async () => {
    // Reproduces the measured failure: a video page titled like the query, whose
    // body says nothing about who produced the record. It scored highly and
    // shared most of the query's words, and the model still invented a name.
    global.fetch = async () =>
      tavilyResponse({
        results: [
          {
            title: 'Zanzibar Nights 1997 album',
            url: 'https://www.example-music-blog.com/zanzibar-nights',
            content: 'Listen to Zanzibar Nights 1997 album tracks.',
            score: 0.92,
          },
        ],
      });
    const out = await searchWeb({ query: 'who produced the album Zanzibar Nights released 1997' });
    assert.equal(out.sources.length, 0, 'a page that omits the asked-for detail must be withheld');
  });

  it('refuses to cite user-generated platforms', async () => {
    for (const host of [
      'https://www.youtube.com/watch?v=abc',
      'https://youtu.be/abc',
      'https://music.youtube.com/watch?v=abc',
      'https://www.reddit.com/r/x/comments/1/',
    ]) {
      global.fetch = async () =>
        tavilyResponse({
          results: [
            {
              title: 'Zanzibar Nights 1997 album produced by',
              url: host,
              content: 'Zanzibar Nights 1997 album was produced by L. Hennrick and M. Sasaji.',
              score: 0.95,
            },
          ],
        });
      const out = await searchWeb({ query: 'who produced the album Zanzibar Nights released 1997' });
      assert.equal(out.sources.length, 0, `${host} must not be citable`);
    }
  });

  it('still cites a host whose name merely contains a blocked name', async () => {
    global.fetch = async () =>
      tavilyResponse({
        results: [
          {
            title: 'notyoutube.com: an explainer',
            url: 'https://notyoutube.com/usd-tzs',
            content: 'The USD to TZS exchange rate today is 2638.',
            score: 0.9,
          },
        ],
      });
    const out = await searchWeb({ query: 'usd to tzs exchange rate today' });
    assert.equal(out.sources.length, 1, 'host matching must not overreach');
  });

  it('drops results with no usable URL', async () => {
    global.fetch = async () =>
      tavilyResponse({
        results: [
          { title: 'a', url: '', content: 'usd to tzs exchange rate today', score: 0.9 },
          { title: 'b', url: 'javascript:alert(1)', content: 'usd to tzs exchange rate today', score: 0.9 },
        ],
      });
    const out = await searchWeb({ query: 'usd to tzs exchange rate today' });
    assert.equal(out.sources.length, 0);
  });
});

describe('searchWeb failure handling', () => {
  it('reports an HTTP error instead of returning partial results', async () => {
    global.fetch = async () => ({ ok: false, status: 432, async text() { return 'quota exceeded'; } });
    const out = await searchWeb({ query: 'usd to tzs' });
    assert.equal(out.sources.length, 0);
    assert.match(out.error, /432/);
  });

  it('reports a network failure without claiming there is nothing to report', async () => {
    global.fetch = async () => { throw new Error('socket hang up'); };
    const out = await searchWeb({ query: 'usd to tzs' });
    assert.equal(out.sources.length, 0);
    assert.match(out.error, /socket hang up/);
  });

  it('reports a timeout as a timeout', async () => {
    global.fetch = async () => {
      const e = new Error('aborted');
      e.name = 'AbortError';
      throw e;
    };
    const out = await searchWeb({ query: 'usd to tzs', timeoutMs: 50 });
    assert.equal(out.sources.length, 0);
    assert.match(out.error, /timed out/i);
  });
});

describe('searchWeb model contract', () => {
  it('tells the model to cite, and not to fill gaps from memory', async () => {
    const out = await searchWeb({ query: '1 usd to tzs exchange rate' });
    assert.match(out.note, /cite/i);
    assert.match(out.note, /memory/i);
  });

  it('labels tavily own synthesis as a third party', async () => {
    const out = await searchWeb({ query: '1 usd to tzs exchange rate' });
    assert.ok(out.tavily_summary, 'the summary is passed through but named as external');
    assert.equal(Object.prototype.hasOwnProperty.call(out, 'answer'), false, 'must not look like the model own answer');
  });

  it('truncates long result bodies to keep the replayed context bounded', async () => {
    global.fetch = async () =>
      tavilyResponse({
        results: [
          {
            title: '1 USD to TZS Exchange Rate',
            url: 'https://www.xe.com/en-us/currencyconverter/usd-tzs',
            content: `usd to tzs exchange rate ${'x'.repeat(50_000)}`,
            score: 0.95,
          },
        ],
      });
    const out = await searchWeb({ query: 'usd to tzs exchange rate' });
    assert.ok(out.results[0].snippet.length <= 700, 'snippet must be bounded');
  });
});
