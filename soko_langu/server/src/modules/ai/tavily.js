// Tavily is the grounding source for anything outside Soko Vibe. Every other
// AI provider was measured and rejected for this: Gemini's OpenAI-compatible
// endpoint 400s on `google_search`/`web_search`, its native surface returns 429,
// and Groq's compound models 404 on this key. Tavily needs a flat HTTP POST and
// returns clean source URLs, which is what the citation contract needs.

const TAVILY_URL = 'https://api.tavily.com/search';

// Tavily is slower than the database tools (measured 3.2s), and the whole
// request still has to fit the client's 25s. 8s leaves room for a model round
// trip on either side of it.
const DEFAULT_TIMEOUT_MS = 8_000;
const MAX_RESULTS = 5;

// Per-result content is truncated because the tool result is replayed into the
// model's context on the next turn, and raw_content can be tens of thousands of
// characters. Five results at this size is roughly 1.5k tokens.
const MAX_CONTENT_CHARS = 700;

// Relevance floor, measured against this key by scoring the same query three
// ways: answerable (0.78-0.95) versus unanswerable (0.09-0.51). A question
// invented out of nothing scores below the floor, so the model receives no
// sources at all and has to say it could not verify.
//
// This exists because of a measured failure: given a fabricated question
// ("Zanzibar Nights 1997"), the model returned a confident invented answer with
// a real-looking URL attached to it. A citation is only worse than no answer if
// it is confidently wrong, so low-relevance results are withheld rather than
// passed along with a caveat the model is free to ignore.
const MIN_RELEVANCE = 0.7;

// Second, independent gate: the share of the query's distinctive words that
// actually appear in the result's title and content.
//
// The floor is 0.75 rather than a rounder number because it was measured
// against the live API. Genuinely answerable queries scored 83-100%:
//   "1 usd to tzs exchange rate"           100%
//   "tanzania data protection law penalty"   83%, 83%, 100%, 100%
//   "capital of tanzania"                   100%
// Irrelevant results scored 17-50%, and a page that reproduced the topic words
// but omitted the one detail actually asked for scored 67%: a blog post titled
// "Zanzibar Nights 1997 album" matches zanzibar/nights/1997/album and never
// mentions a producer, yet the model read it and named one anyway. Topic overlap
// is not the same as answering, so the floor sits above the best irrelevant
// result and below the worst genuine one.
const MIN_COVERAGE = 0.75;

// User-generated platforms, excluded from citations outright.
//
// This closes the last measured fabrication. A question about a made-up 1997
// album still found a YouTube upload whose title matched the query well enough
// to clear both gates above, and the model then confidently named a producer
// from a video page that never said it. Nothing on these hosts is attributable,
// so a citation drawn from them cannot be checked by the reader and must not be
// offered. Deduplicated to bare hostnames so the whole domain is covered.
const UNCITABLE_HOSTS = new Set([
  'youtube.com', 'youtu.be', 'tiktok.com', 'facebook.com', 'fb.com', 'instagram.com',
  'x.com', 'twitter.com', 'reddit.com', 'pinterest.com', 'quora.com', 'medium.com',
  'tiktokcdn.com', 'pinimg.com', 'imgur.com', '9gag.com', 'weibo.com', 'vk.com',
]);

/**
 * Whether a result's host is one we are willing to cite.
 *
 * Host matching is on full and leading subdomain labels, so
 * `music.youtube.com` and `www.youtube.com` are both caught while
 * `notyoutube.com` is not.
 */
function isCitable(url) {
  let host;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    return false;
  }
  const labels = host.split('.');
  for (let i = 0; i < labels.length - 1; i++) {
    if (UNCITABLE_HOSTS.has(labels.slice(i).join('.'))) return false;
  }
  return true;
}

// Query words too common to prove a result is on-topic, and words the user did
// not really ask about.
const STOP_WORDS = new Set([
  'the', 'a', 'an', 'of', 'for', 'to', 'in', 'on', 'is', 'and', 'or', 'by', 'at', 'as',
  'what', 'who', 'when', 'where', 'which', 'how', 'why', 'does', 'do', 'did', 'is',
  'tell', 'give', 'show', 'me', 'my', 'i', 'you', 'it', 'that', 'this', 'with',
  'today', 'current', 'currently', 'latest', 'now', 'rate', 'price', 'please',
]);

/**
 * Share of the query's distinctive words found in a result.
 *
 * Short words and question words are dropped, since a page about a currency
 * converter will match "rate" and "today" even when it is about the wrong
 * currency, which is exactly the kind of coincidence that produced a confident
 * answer with a citation that did not support it.
 */
function coverage(query, result) {
  const terms = [...new Set(
    query.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length > 2 && !STOP_WORDS.has(t))
  )];
  if (!terms.length) return 1;
  const text = `${result.title || ''} ${result.content || ''}`.toLowerCase();
  return terms.filter((t) => text.includes(t)).length / terms.length;
}

/**
 * Searches the public web and returns ranked results with their source URLs.
 *
 * Returns `{ sources }` alongside the payload because the tool loop harvests
 * that field to build the citation list the client renders. A result without a
 * real http(s) URL is dropped rather than passed on: a citation that cannot be
 * opened is worse than no citation, because it invites the reader to trust it.
 */
async function searchWeb({ query, maxResults, timeoutMs }) {
  const q = String(query || '').trim().slice(0, 300);
  if (!q) return { results: [], sources: [], note: 'A query is required.' };

  const key = process.env.TAVILY_API_KEY;
  if (!key) {
    return {
      results: [],
      sources: [],
      note: 'Web search is not configured on this server, so I cannot verify anything outside Soko Vibe right now.',
    };
  }

  const budget = Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), budget);

  let payload;
  try {
    const resp = await fetch(TAVILY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: controller.signal,
      body: JSON.stringify({
        api_key: key,
        query: q,
        // `basic` keeps the tool inside the loop's latency budget. `advanced`
        // crawls each result and was measured slower than the client's timeout.
        search_depth: 'basic',
        max_results: Math.min(Math.max(1, Number(maxResults) || MAX_RESULTS), MAX_RESULTS),
        // Tavily's own synthesis is passed through, but labelled, so the model
        // cites the individual sources rather than presenting Tavily's summary
        // as its own finding.
        include_answer: true,
      }),
    });

    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      console.error(`[ai] tavily HTTP ${resp.status}: ${detail.slice(0, 200)}`);
      return { results: [], sources: [], error: `web search failed (HTTP ${resp.status})` };
    }
    payload = await resp.json();
  } catch (e) {
    // A failed search must read as "I could not check", never as "there is
    // nothing to report" — otherwise the model treats silence as a fact.
    const reason = e.name === 'AbortError' ? `timed out after ${budget}ms` : e.message;
    console.error('[ai] tavily request failed:', reason);
    return { results: [], sources: [], error: `web search ${reason}` };
  } finally {
    clearTimeout(timer);
  }

  const sources = [];
  const results = [];
  let withheld = 0;
  for (const r of payload?.results || []) {
    const url = String(r?.url || '');
    if (!/^https?:\/\//i.test(url)) continue;
    if (!isCitable(url)) continue;
    // Both gates, or nothing. They fail differently and are deliberately
    // redundant: MIN_RELEVANCE is Tavily's judgement of topical similarity,
    // which occasionally admits a page that merely shares a title, while
    // coverage checks the result text directly, which occasionally still lets
    // through a page that shares every topic word without answering. A
    // fabricated question has to fool both before it reaches the model.
    if (Number(r.score) < MIN_RELEVANCE || coverage(q, r) < MIN_COVERAGE) {
      withheld++;
      continue;
    }
    const source = { ref: `web-${sources.length + 1}`, title: r.title || url, url };
    sources.push(source);
    results.push({
      n: sources.length,
      title: source.title,
      url,
      snippet: String(r.content || '').slice(0, MAX_CONTENT_CHARS),
    });
  }

  // Withholding is the whole point: an empty source list leaves the model with
  // nothing to attach to an answer, so it has to report that it could not check.
  if (!results.length) {
    return {
      query: q,
      results: [],
      sources: [],
      note: withheld
        ? 'Search found nothing relevant enough to answer this. Tell the user you could not find a source for it. Do not answer from your own knowledge.'
        : 'No web results found. Say plainly that you could not verify this.',
    };
  }

  return {
    query: q,
    // Labelled as a third party's synthesis, not an answer to adopt.
    tavily_summary: payload?.answer ? String(payload.answer).slice(0, MAX_CONTENT_CHARS) : null,
    results,
    sources,
    note: 'Cite the numbered URL for any claim taken from it. If these do not actually answer the question, say so rather than filling the gap from memory.',
  };
}

module.exports = { searchWeb, TAVILY_URL, MAX_RESULTS };
