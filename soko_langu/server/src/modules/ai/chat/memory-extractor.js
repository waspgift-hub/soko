// Turns a stretch of conversation into a small set of durable preferences.
//
// Runs AFTER a turn completes and off the request's critical path (§7 asks for
// asynchronous extraction; §16 asks for async memory extraction). A memory that
// failed to extract costs the user a slightly less personal reply, so it must never
// be able to fail a message.
//
// The extractor is deterministic, like the title generator, and for the same
// reasons plus one more: a memory is something the AI will assert back to the user
// as a fact about them, so it has to be reproducible and auditable. "Why does the
// AI think I speak Swahili?" must have an answer that is a counter of observed
// messages, not "the model felt like it". Nothing here calls a provider.
//
// ── The hard rules, and where they are enforced ──
//
// 1. SENSITIVE DATA IS NEVER STORED. Enforced twice, deliberately. `extract()`
//    drops any candidate whose KEY or VALUE matches SENSITIVE_PATTERNS, and
//    `isSensitiveText()` is also applied to whole messages before extraction so a
//    message carrying a credential cannot influence any candidate. The second
//    check exists because a pattern can be spread across two candidates — the
//    value "hunter2" alone looks innocuous, but arriving inside a message that also
//    contains the word "password" it is not.
//
// 2. SENSITIVE ATTRIBUTES ARE NEVER INFERRED. There is no code path that turns a
//    user message into a stored trait of health, religion, ethnicity, political
//    leaning, sexuality or criminal history. `FORBIDDEN_KEYS` rejects them by name
//    as a backstop, so even a future contributor adding a detector cannot add one
//    of those by accident — the key never gets to be written.
//
// 3. A TEMPORARY STATEMENT IS NOT A PREFERENCE. "In Kiswahili only today" is not a
//    language preference. TEMPORAL_HINTS lower confidence and raise the bar for
//    persistence rather than being trusted, so a one-off phrasing cannot install a
//    permanent trait.
//
// 4. FREQUENCY IS REQUIRED. Nothing is stored off a single observation unless the
//    user stated it as an explicit standing instruction.

const store = require('./chat-store');
const { TOPICS } = require('./title-generator');

// ── Sensitive-data patterns ─────────────────────────────────────────────────

// Patterns for things that must never be written anywhere, including chat
// messages. Each is intentionally narrow: an over-broad digit rule would redact
// order numbers and prices, which are ordinary Soko Vibe content.
const SENSITIVE_PATTERNS = [
  {
    name: 'password',
    re: /\b(?:password|passwd|pass\s?code|pin\s?code|my\s+pin\b|secret\s+key|api\s*key)\b\s*(?:is|:|=)?\s*\S+/i,
  },
  { name: 'otp', re: /\b(?:otp|verification\s+code|one[\s-]?time\s+(?:code|password|pin)|confirm\s+code|code\s+sent)\b\s*(?:is|:|=)?\s*\d{3,8}/i },
  // Card numbers, with or without separators. 13-19 digits is the real range,
  // which excludes a TSh amount or an order id.
  { name: 'card', re: /\b(?:\d[ -]?){13,19}\b/ },
  { name: 'cvv', re: /\b(?:cvv|cvc|cvv2|security\s+code)\b\s*(?:is|:|=)?\s*\d{3,4}/i },
  { name: 'bank_account', re: /\b(?:account\s+number|acct\s*(?:no|number)|bank\s+account|akaunti\s+ya\s+benki|namba\s+ya\s+akaunti)\b\s*(?:is|:|=)?\s*\d{6,}/i },
  { name: 'bearer_token', re: /\b(?:bearer|authorization)\s+[A-Za-z0-9._~+/-]{20,}=*/i },
  { name: 'jwt', re: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/ },
  { name: 'mpesa_secret', re: /\b(?:mpesa\s+(?:pin|code|secret)|sacco\s+pin)\b\s*(?:is|:|=)?\s*\S+/i },
  { name: 'id_number', re: /\b(?:national\s+id|nin\s*(?:number)?|huduma\s+namba|id\s+number)\b\s*(?:is|:|=)?\s*[A-Za-z0-9]{6,}/i },
];

// Attribute names that are refused outright. This is a name-level block, so it
// holds even if a detector for the attribute were added by mistake.
const FORBIDDEN_KEYS = new Set([
  'password', 'passcode', 'pin', 'otp', 'card_number', 'cvv', 'bank_account',
  'account_number', 'api_key', 'token', 'auth_token', 'bearer_token',
  'religion', 'religious_affiliation', 'ethnicity', 'tribe', 'race',
  'health', 'medical_condition', 'hiv_status', 'pregnancy', 'disability',
  'sexual_orientation', 'sexual_preference', 'political_party', 'politics',
  'political_affiliation', 'criminal_record', 'conviction',
  'date_of_birth', 'age', 'gender', 'sex', 'marital_status',
  'national_id', 'nin', 'passport_number', 'tax_id',
]);

/** True when [text] contains anything that must not be persisted or sent to a model. */
function isSensitiveText(text) {
  const value = String(text || '');
  return SENSITIVE_PATTERNS.some((p) => p.re.test(value));
}

function isForbiddenKey(key) {
  return FORBIDDEN_KEYS.has(String(key || '').toLowerCase().replace(/\s+/g, '_'));
}

// ── Language ────────────────────────────────────────────────────────────────

const SW_WORDS = /\b(na|ya|kwa|ni|wa|za|la|cha|vya|katika|kama|kwenye|ili|nini|vipi|wapi|habari|karibu|asante|sina|poa|ndefu|mfupi|bidhaa|duka|bei|maagizo|malipo|watumiaji|ninakuuliza|naomba|msaada)\b/;
const EN_WORDS = /\b(the|and|for|you|with|how|what|where|can|could|would|should|please|about|from|your|my|is|are|do|does|help|sell|buy|price|store|shop)\b/i;

/**
 * Scores a set of messages as Swahili or English.
 *
 * Returns null when the two are too close to call. Storing `preferred_language`
 * from a 20%-margin reading would be worse than storing nothing: the AI would
 * assert a language preference the user never expressed and never be able to
 * explain it.
 */
function detectPreferredLanguage(messages) {
  let sw = 0;
  let en = 0;
  for (const m of messages) {
    sw += (String(m.content).match(new RegExp(SW_WORDS, 'g')) || []).length;
    en += (String(m.content).match(new RegExp(EN_WORDS, 'g')) || []).length;
  }
  const total = sw + en;
  if (total < 5) return null;
  const swShare = sw / total;
  if (swShare >= 0.6) return { value: 'Swahili', confidence: Math.min(0.95, 0.5 + swShare * 0.4) };
  if (swShare <= 0.25) return { value: 'English', confidence: Math.min(0.95, 0.5 + (1 - swShare) * 0.4) };
  return null;
}

// ── Response style ──────────────────────────────────────────────────────────

const CONCISE = /\b(?:short|shorter|brief|briefly|concise|quick|quickly|simply|just tell me|no need for long|don'?t explain too much|keep it short|one line|short answer)\b|\b(?:mufupi|fupi|short|ghafla|kifupi|usiungeue|chochote kizuri|maneno machache)\b/i;
const DETAILED = /\b(?:detail|detailed|in depth|thorough|step by step|explain everything|explain fully|elaborate|walk me through)\b|\b(?:maelezo|kina|makamilifu|hatua kwa hatua|eleza kwa upana)\b/i;

// Phrasing that makes a style request apply to THIS turn only. Not a rejection —
// the statement is simply down-weighted so it cannot become a durable preference.
const TEMPORAL_HINTS = /\b(?:for now|today only|just this once|this time only|for this message|right now|temporarily|once|baada ya hii|kwa sasa|simu hii tu|mara hii)\b/i;

/**
 * Whether a style request is scoped to a single turn.
 *
 * Checked per message so a user who says "be brief" once in a long conversation and
 * "explain everything" the next turn does not get both recorded and averaged into
 * incoherence.
 */
function isTemporary(text) {
  return TEMPORAL_HINTS.test(String(text || ''));
}

function detectResponseStyle(messages) {
  let concise = 0;
  let detailed = 0;
  for (const m of messages) {
    if (isTemporary(m.content)) continue;
    if (CONCISE.test(String(m.content))) concise += 1;
    if (DETAILED.test(String(m.content))) detailed += 1;
  }
  if (concise === 0 && detailed === 0) return null;
  if (concise === detailed) return null;
  const total = concise + detailed;
  const value = concise > detailed ? 'concise' : 'detailed';
  // Confidence scales with how lopsided the evidence is, and stays under the
  // single-observation floor below, so one "be brief" never installs a trait.
  const confidence = Math.min(0.9, 0.3 + Math.abs(concise - detailed) / total);
  return { value, confidence, observations: total };
}

// ── Topics ──────────────────────────────────────────────────────────────────

/**
 * Counts the conversations' dominant topic.
 *
 * Derived from the topic table the title generator already uses rather than a
 * second classifier, so a memory and a conversation title can never disagree about
 * what a conversation was about.
 */
function detectFrequentTopic(messages) {
  const tally = new Map();
  for (const m of messages) {
    const lowered = String(m.content).toLowerCase();
    for (const topic of TOPICS) {
      if (topic.label === 'Greetings') continue;
      if (topic.words.some((w) => lowered.includes(w))) {
        tally.set(topic.label, (tally.get(topic.label) || 0) + 1);
      }
    }
  }
  if (!tally.size) return null;
  const [label, count] = [...tally.entries()].sort((a, b) => b[1] - a[1])[0];
  if (count < 2) return null;
  return {
    value: label,
    // One mention is an accident, two is a coincidence, four is a habit.
    confidence: Math.min(0.85, 0.25 + count * 0.15),
    observations: count,
  };
}

// ── Explicit standing instructions ──────────────────────────────────────────

const EXPLICIT_RULES = [
  {
    key: 'preferred_language',
    // "always reply in Swahili", "from now on answer me in English", "jibu kwa
    // Kiswahili kila wakati"
    re: /\b(?:always|from now on|stop|only)\b[^.!?\n]{0,40}\b(?:reply|answer|respond|write|talk)\b[^.!?\n]{0,30}\b(?:in|with)\b\s*([a-z]{3,20})/i,
    normalize: (m) => {
      const v = String(m[1] || '').toLowerCase();
      if (/kiswahili|swahili|kiswahili/.test(v)) return 'Swahili';
      if (/english|kiingereza|ingereza/.test(v)) return 'English';
      return null;
    },
  },
  {
    key: 'response_style',
    re: /\b(?:always|from now on)\b[^.!?\n]{0,30}\b(?:be|keep|stay|make)\b[^.!?\n]{0,20}\b(?:brief|short|concise|simple|detailed|thorough)\b/i,
    normalize: (m) => (/\b(?:brief|short|concise|simple)\b/i.test(m[0]) ? 'concise' : 'detailed'),
  },
  {
    key: 'seller_status',
    re: /\b(?:i am|i'?m|I'm)\s+(?:a|an)\s+(seller|buyer|shop owner|store owner|vendor)\b/i,
    normalize: (m) => {
      const v = String(m[1]).toLowerCase();
      if (v === 'seller' || v === 'vendor' || v.includes('owner')) return 'seller';
      if (v === 'buyer') return 'buyer';
      return null;
    },
  },
  {
    key: 'tone_preference',
    re: /\b(?:please\s+)?(?:be|reply|answer|respond)\s+(?:polite|formal|casual|friendly|respectful|professional)\b/i,
    normalize: (m) => String(m[1]).toLowerCase(),
  },
];

function detectExplicit(messages) {
  const found = new Map();
  for (const m of messages) {
    const text = String(m.content || '');
    if (isSensitiveText(text)) continue;
    for (const rule of EXPLICIT_RULES) {
      const match = text.match(rule.re);
      if (!match) continue;
      const value = rule.normalize(match);
      if (!value) continue;
      // An explicit instruction is a stated standing preference, so it is trusted
      // outright — but it is still lowered when the sentence is time-scoped.
      found.set(rule.key, {
        value,
        confidence: isTemporary(text) ? 0.45 : 0.9,
        source: 'explicit',
      });
    }
  }
  return [...found.entries()].map(([key, v]) => ({ key, ...v }));
}

// ── Public API ──────────────────────────────────────────────────────────────

// Below this, nothing is written unless the user said it outright. The floor is
// what stops a single "hmm what's 2+2" from recording a permanent trait.
const MIN_CONFIDENCE = 0.5;
const EXPLICIT_SOURCE = 'explicit';

/**
 * Derives candidate memories from a conversation window.
 *
 * Pure and synchronous — no I/O — so it is directly testable and safe to call on
 * the request path in tests.
 *
 * @param {object[]} messages user-authored turns, oldest first
 * @returns {object[]} candidates ready for `persistCandidates`
 */
function extract(messages) {
  const userTurns = (messages || []).filter(
    (m) => m && m.role === 'user' && String(m.content || '').trim()
  );
  if (!userTurns.length) return [];

  // A credential-bearing message is dropped from the evidence set entirely, so it
  // cannot nudge a language, style or topic counter on its way to being stored.
  const safe = userTurns.filter((m) => !isSensitiveText(m.content));

  const candidates = [
    ...detectExplicit(safe),
    buildCandidate('preferred_language', detectPreferredLanguage(safe)),
    buildCandidate('response_style', detectResponseStyle(safe)),
    buildCandidate('frequent_topic', detectFrequentTopic(safe)),
  ];

  return candidates.filter((c) => c && !isForbiddenKey(c.key) && !isSensitiveText(c.value));
}

function buildCandidate(key, found) {
  if (!found) return null;
  return { key, ...found };
}

/**
 * Writes candidates that clear the confidence floor, newest evidence first.
 *
 * Ordered by descending confidence so that when several qualify, the strongest is
 * written last and ends up as the surviving value after the reinforcement maths in
 * `upsertMemory`.
 */
async function persistCandidates({ userId, candidates }) {
  const eligible = (candidates || [])
    .filter((c) => c && c.confidence >= MIN_CONFIDENCE || c.source === EXPLICIT_SOURCE)
    .sort((a, b) => a.confidence - b.confidence);

  const written = [];
  for (const candidate of eligible) {
    try {
      const result = await store.upsertMemory({
        userId,
        key: candidate.key,
        value: candidate.value,
        confidence: candidate.confidence,
        source: candidate.source || 'inferred',
      });
      written.push(result);
    } catch (err) {
      // One unwritable memory must not abort the rest, and must never surface as a
      // failed message: extraction is a background nicety.
      console.warn(`[ai] memory upsert failed (${candidate.key}): ${err.message}`);
    }
  }
  return written;
}

/**
 * The full background job: extract from recent user turns and persist.
 *
 * Never throws. Called fire-and-forget from the chat route after a completed turn.
 */
async function runExtraction({ userId, messages, conversationId }) {
  try {
    const preferences = await store.getPreferences({ userId });
    if (preferences.memoryEnabled === false) return { written: 0, skipped: 'memory_disabled' };
    if (preferences.chatHistoryEnabled === false) return { written: 0, skipped: 'history_disabled' };

    const candidates = extract(messages);
    if (!candidates.length) return { written: 0, skipped: 'no_candidates' };

    const written = await persistCandidates({ userId, candidates });
    console.log(
      `[ai] memory extraction: ${written.length} memory row(s) from ${conversationId}`
    );
    return { written: written.length, skipped: null };
  } catch (err) {
    console.error('[ai] memory extraction failed:', err.message);
    return { written: 0, skipped: 'error' };
  }
}

module.exports = {
  extract,
  runExtraction,
  persistCandidates,
  isSensitiveText,
  isForbiddenKey,
  detectPreferredLanguage,
  detectResponseStyle,
  detectFrequentTopic,
  detectExplicit,
  SENSITIVE_PATTERNS,
  FORBIDDEN_KEYS,
  MIN_CONFIDENCE,
};