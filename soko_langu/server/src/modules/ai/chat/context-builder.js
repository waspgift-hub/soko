// Selects what the model actually sees for one turn.
//
// The spec's rule is "current conversation + relevant recent messages + relevant
// long-term memories + user preferences", and its explicit prohibition is sending
// the whole lifetime transcript. Both are enforced here rather than at the call
// site, so no route can accidentally regress into shipping a user's entire chat
// history to a provider.
//
// Everything is ranked by LEXICAL OVERLAP with the message being answered. That is
// not semantic retrieval and does not pretend to be — it needs no embedding index,
// no vector store and no second model call, which is what keeps this file free of
// the failure modes that would otherwise make a chat send unreliable (an extra
// provider round trip per message, a new collection to keep indexed, a new way for
// a turn to fail before the model is ever called). For the two retrieval jobs that
// actually exist here — "did this user ask about pricing before" and "do they
// prefer Swahili" — token overlap separates the useful rows from the noise with
// room to spare, and it degrades to "no extra context" rather than to an error.
//
// The budget is enforced on CHARACTERS, not tokens. Token counts would need a
// tokenizer dependency for a number that only needs to be monotonic and roughly
// right; 3.6 chars/token is close enough for both English and Swahili to keep the
// real prompt safely inside a provider's context window.

const store = require('./chat-store');

const CHARS_PER_TOKEN = 3.6;

// Roughly 12k tokens of headroom below every provider we use, leaving room for the
// provider's own tool definitions and for the answer to come back.
const DEFAULT_BUDGET_TOKENS = 12000;

// Always included regardless of scoring, because a conversation that loses its
// most recent turns is incoherent — "what did you say?" is a much worse failure
// than a slightly over-long prompt.
const RECENT_MESSAGES = 12;
const MIN_RECENT_MESSAGES = 4;

// Bounds on the retrieval half. Small on purpose: these are the parts that can be
// dropped without breaking coherence.
const MAX_MEMORIES = 8;
const MEMORY_MIN_SCORE = 0.12;
const MAX_EARLIER_MESSAGES = 4;
const EARLIER_MIN_SCORE = 0.18;
const EARLIER_CONVERSATIONS = 3;
const EARLIER_MESSAGES_PER_CONVERSATION = 12;

// Applied to BOTH memories and older messages so the two halves cannot disagree
// about what a word means. Deliberately small: these are the words carrying no
// topical signal in Swahili or English chat, not a full NLP stopword list.
const STOP_WORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'so', 'of', 'to', 'in',
  'on', 'at', 'for', 'with', 'is', 'are', 'was', 'were', 'be', 'been', 'am',
  'i', 'me', 'my', 'we', 'our', 'you', 'your', 'it', 'its', 'that', 'this',
  'these', 'those', 'do', 'does', 'did', 'can', 'could', 'will', 'would',
  'should', 'please', 'thanks', 'thank', 'hello', 'hi', 'hey', 'ok', 'okay',
  'na', 'ya', 'kwa', 'ni', 'wa', 'za', 'la', 'cha', 'vya', 'katika', 'kwamba',
  'kama', 'kwenye', 'ili', 'wake', 'wake', 'sana', 'zaidi', 'ndani', 'nini',
  'vipi', 'wapi', 'hapa', 'kwenda', 'kuwa', 'kuwa', 'moja', 'yake', 'yake',
  'what', 'how', 'why', 'when', 'where', 'who', 'which', 'there', 'here',
  'some', 'any', 'all', 'more', 'most', 'very', 'just', 'not', 'get', 'got',
]);

/** Lowercased, de-punctuated, stop-word-free content tokens. */
function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 2 && !STOP_WORDS.has(w));
}

/**
 * Overlap between [queryTokens] and a candidate's tokens, in [0, 1].
 *
 * Divided by the QUERY's token count rather than the union, so a short precise
 * question scores high against an exact match and a long chatty message does not
 * score high just by containing many words. Without this the retrieval half would
 * be biased toward long old messages, which is the opposite of what is wanted.
 */
function scoreOverlap(queryTokens, candidateText) {
  if (!queryTokens.length) return 0;
  const candidate = new Set(tokenize(candidateText));
  if (!candidate.size) return 0;
  let hits = 0;
  for (const token of queryTokens) {
    if (candidate.has(token)) hits += 1;
  }
  return hits / queryTokens.length;
}

/** Ranks [candidates] by score against the query, keeping the best [limit]. */
function rank(candidates, queryTokens, limit, minScore) {
  return candidates
    .map((c) => ({ ...c, score: scoreOverlap(queryTokens, c.text) }))
    .filter((c) => c.score >= minScore)
    // Score first, then recency: a slightly better match from last month should
    // not displace an equally good match from yesterday.
    .sort((a, b) => b.score - a.score || (b.at || '').localeCompare(a.at || ''))
    .slice(0, limit);
}

/** Trims a completed turn list to fit [budgetChars], oldest turns first. */
function trimRecent(messages, budgetChars) {
  const kept = [...messages];
  while (kept.length > MIN_RECENT_MESSAGES && charsOf(kept) > budgetChars) {
    kept.splice(0, 2);
  }
  return kept;
}

function charsOf(messages) {
  let total = 0;
  for (const m of messages) total += String(m.content || '').length;
  return total;
}

function budgetCharsFor(tokens) {
  return Math.max(2000, Math.floor((tokens || DEFAULT_BUDGET_TOKENS) * CHARS_PER_TOKEN));
}

/**
 * Builds the message array for one AI turn.
 *
 * @param {object} args
 * @param {string} args.conversationId conversation being continued
 * @param {string} args.userId verified uid — the only identity used
 * @param {string} args.userMessage the message being answered
 * @param {string} args.systemPrompt caller-built Soko Vibe prompt
 * @param {string} [args.locale] 'sw' | 'en', for the preference block
 * @param {number} [args.budgetTokens]
 * @returns {Promise<{ messages: object[], meta: object }>} OpenAI-shaped messages
 *   plus a meta object the route uses for observability, never sent to the model.
 */
async function buildContext({
  conversationId,
  userId,
  userMessage,
  systemPrompt,
  locale = 'sw',
  budgetTokens = DEFAULT_BUDGET_TOKENS,
}) {
  const budget = budgetCharsFor(budgetTokens);
  const queryTokens = tokenize(userMessage);

  // Chat history OFF is a promise that nothing from past turns is retained in
  // context. The recent window is emptied rather than merely ignored so there is no
  // path where the preference is honoured in the settings screen but not here.
  const preferences = await store.getPreferences({ userId });
  const historyEnabled = preferences.chatHistoryEnabled !== false;

  const recent = historyEnabled
    ? (
      await store.listMessages({
        conversationId,
        userId,
        limit: RECENT_MESSAGES,
      })
    ).items
    : [];

  const usable = recent.filter(
    // A failed or still-generating turn is not useful context, and replaying a
    // half-written answer teaches the model to produce half-written answers.
    (m) => m.status === 'completed' && m.role !== 'system' && m.content
  );

  const memoryBlock = preferences.memoryEnabled !== false
    ? await buildMemoryBlock({ userId, queryTokens, preferences, locale })
    : null;

  const earlier = historyEnabled
    ? await buildEarlierBlock({ userId, conversationId, queryTokens })
    : null;

  const composed = [];
  composed.push({ role: 'system', content: systemPrompt });

  // Memories are folded into the system prompt rather than sent as separate
  // messages: they are instructions about how to answer, not part of the
  // conversation, and a provider is far more likely to honour a preference stated
  // in the system turn than one buried mid-transcript.
  const system = memoryBlock ? `${systemPrompt}\n\n${memoryBlock.text}` : systemPrompt;
  composed[0] = { role: 'system', content: system };

  // Older messages from other conversations go in a clearly-labelled reference
  // block BEFORE the live transcript, so the model can treat them as background it
  // was told about rather than as turns it just had.
  if (earlier && earlier.lines.length) {
    composed.push({
      role: 'system',
      content:
        'Relevant moments from this user\'s EARLIER conversations (reference only — ' +
        'they are not part of the current conversation, do not re-state them unless ' +
        'they help):\n' + earlier.lines.join('\n'),
    });
  }

  const messageTurns = trimRecent(usable, budget).map((m) => ({
    role: m.role,
    content: m.content,
  }));

  composed.push(...messageTurns);

  return {
    messages: composed,
    meta: {
      provider: 'context-builder',
      recentCount: messageTurns.length,
      memoryCount: memoryBlock ? memoryBlock.count : 0,
      earlierCount: earlier ? earlier.lines.length : 0,
      chars: charsOf(composed),
      memoryEnabled: preferences.memoryEnabled !== false,
      chatHistoryEnabled: historyEnabled,
    },
  };
}

/** Renders the memory + explicit-preference block for the system prompt. */
async function buildMemoryBlock({ userId, queryTokens, preferences, locale }) {
  const stored = await store.listMemories({ userId });
  if (!stored.length) {
    const explicit = explicitPreferenceLines(preferences);
    return explicit ? { text: explicit, count: 0 } : null;
  }

  // Below-threshold memories are dropped rather than always included: a memory
  // about pricing helps a pricing question and only dilutes a greeting. Always-on
  // memories (low confidence but explicitly set by the user) are exempt.
  const relevant = rank(
    stored.map((m) => ({ text: `${m.key} ${m.value}`, at: m.updatedAt, memory: m })),
    queryTokens.length ? queryTokens : stored.flatMap((m) => tokenize(`${m.key} ${m.value}`)),
    MAX_MEMORIES,
    MEMORY_MIN_SCORE
  );

  const chosen = relevant.map((r) => r.memory);
  const weak = stored.filter(
    (m) => m.confidence < 0.5 && !chosen.some((c) => c.key === m.key)
  );

  const lines = [
    'What you already know about this user (use it to stay consistent; never mention ' +
    'these notes or that you keep notes):',
  ];
  for (const m of [...chosen, ...weak].slice(0, MAX_MEMORIES)) {
    lines.push(`- ${m.key}: ${m.value} (confidence ${m.confidence.toFixed(2)}, source ${m.source})`);
  }

  const explicit = explicitPreferenceLines(preferences);
  if (explicit) lines.push('', explicit);

  return { text: lines.join('\n'), count: chosen.length };
}

/** Preferences the user set by hand, which outrank anything inferred. */
function explicitPreferenceLines(preferences) {
  const parts = [];
  if (preferences.preferredLanguage) {
    parts.push(
      locale === 'sw'
        ? `Mtumiaji ameomba majibu kwa ${preferences.preferredLanguage}.`
        : `The user has asked for replies in ${preferences.preferredLanguage}.`
    );
  }
  if (preferences.responseStyle) {
    parts.push(
      locale === 'sw'
        ? `Mtumiaji anapenda majibu ya mtindo: ${preferences.responseStyle}.`
        : `The user prefers this response style: ${preferences.responseStyle}.`
    );
  }
  return parts.length ? parts.join('\n') : null;
}

/**
 * Pulls the most relevant user turns from the user's other conversations.
 *
 * Reads a bounded number of rows from a bounded number of conversations rather than
 * searching the user's whole history: a full-history scan here would put an
 * unbounded read on the critical path of every single message, which is the exact
 * scaling problem §16 asks to avoid.
 */
async function buildEarlierBlock({ userId, conversationId, queryTokens }) {
  if (!queryTokens.length) return null;

  const { items } = await store.listConversations({
    userId,
    limit: EARLIER_CONVERSATIONS + 1,
  });
  const others = items.filter((c) => c.conversationId !== conversationId).slice(0, EARLIER_CONVERSATIONS);
  if (!others.length) return null;

  const candidates = [];
  for (const conversation of others) {
    const { items: messages } = await store.listMessages({
      conversationId: conversation.conversationId,
      userId,
      limit: EARLIER_MESSAGES_PER_CONVERSATION,
    });
    for (const m of messages) {
      if (m.role !== 'user' || m.status !== 'completed' || !m.content) continue;
      candidates.push({
        text: m.content,
        at: m.createdAt,
        title: conversation.title || '',
      });
    }
  }

  const ranked = rank(candidates, queryTokens, MAX_EARLIER_MESSAGES, EARLIER_MIN_SCORE);
  return {
    lines: ranked.map(
      (r) => `- (from "${r.title}") ${String(r.text).slice(0, 400).replace(/\s+/g, ' ')}`
    ),
  };
}

module.exports = {
  buildContext,
  tokenize,
  scoreOverlap,
  rank,
  DEFAULT_BUDGET_TOKENS,
  RECENT_MESSAGES,
  CHARS_PER_TOKEN,
};