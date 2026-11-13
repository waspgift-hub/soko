// Deterministic chat titles from the first useful user message.
//
// No model call, deliberately. A title is one short noun phrase, and the spec is
// explicit that spending a provider call to produce one is not worth it: every
// conversation would pay an extra round trip and a token charge for a string this
// file derives in microseconds. It also cannot fail, cannot be rate limited, and
// cannot return a title in the wrong language.
//
// The pipeline is: strip the conversational scaffolding ("how do I", "can you",
// "nini", "vipi"), then either match a known topic and use its canonical label, or
// fall back to the longest meaningful words the message still has. So "How do I
// advertise my store?" becomes "Advertising" from the topic table, and an
// unrecognised question becomes a title-cased fragment of its own words.

const MAX_TITLE_CHARS = 60;
const MAX_TITLE_WORDS = 5;

// Topic labels, in the app's two languages. First match wins, so the ordering of
// this array is the matching priority — a message about advertising a shop on
// Instagram should land on `advertising`, not `instagram`, and `advertising` is
// therefore checked first.
const TOPICS = [
  {
    label: 'Advertising',
    labelSw: 'Udanganyaji',
    words: ['advertis', 'advertiz', 'marketing', 'promote', 'promot', 'campaign',
      'reach more', 'get customers', 'find buyers', 'reach out', 'brand',
      'udanganyaji', 'kuenezwa', 'kampeni', 'promote', 'soko'],
  },
  {
    label: 'Pricing',
    labelSw: 'Bei',
    words: ['price', 'pricing', 'cost', 'cheap', 'expensive', 'discount', 'margin',
      'bei', 'bei ya', 'ghali', 'punguzo', 'kipunguzo', 'faida'],
  },
  {
    label: 'Store Setup',
    labelSw: 'Kupanga Duka',
    words: ['shop', 'store', 'stall', 'booth', 'kiosk', 'open a', 'setup',
      'start selling', 'register', 'duka', 'kioski', 'podi', 'anzia', 'fungua'],
  },
  {
    label: 'Product Ideas',
    labelSw: 'Mawazo ya Bidhaa',
    words: ['what to sell', 'product idea', 'idea', 'ideas', 'suggest',
      'nini ya kuuza', 'bidhaa', 'wazo', 'mawazo', 'changia', 'pendekeza'],
  },
  {
    label: 'Orders & Delivery',
    labelSw: 'Maagizo na Usambazaji',
    words: ['order', 'delivery', 'deliver', 'shipping', 'ship', 'courier',
      'maagizo', 'agizo', 'usambazaji', 'tuma', 'mwalimu', 'deliver'],
  },
  {
    label: 'Payments',
    labelSw: 'Malipo',
    words: ['payment', 'payments', 'mpesa', 'wallet', 'payout', 'withdraw',
      'malipo', 'kulipa', 'pesa', 'akaunti ya benki', 'kubeba', 'kiwango'],
  },
  {
    label: 'Shipping & Logistics',
    labelSw: 'Usafirishaji',
    words: ['logistics', 'transport', 'shipment', 'courier company',
      'usafirishaji', 'mabeba', 'usafirishaji'],
  },
  {
    label: 'Soko Vibe App',
    labelSw: 'Programu ya Soko Vibe',
    words: ['soko vibe', 'sokovibe', 'the app', 'application', 'app',
      'programu', 'aplikesheni'],
  },
  {
    label: 'Writing',
    labelSw: 'Uandishi',
    words: ['write', 'writing', 'caption', 'description', 'copy', 'post',
      'andika', 'maandishi', 'alama', 'kuelezea', 'machapisho'],
  },
  {
    label: 'Coding Help',
    labelSw: 'Usaidizi wa Programu',
    words: ['code', 'coding', 'bug', 'error', 'function', 'api', 'database',
      'flutter', 'dart', 'javascript', 'python', 'server', 'deploy',
      'programu ya', 'hitilafu', 'kosa', 'funguo', 'hifadhi ya taarifa'],
  },
  {
    label: 'Business Ideas',
    labelSw: 'Mawazo ya Biashara',
    words: ['business', 'start a business', 'biashara', 'kipa', 'biashara ya',
      'maeneo', 'venture'],
  },
  {
    label: 'Greetings',
    labelSw: 'Salamu',
    words: ['hello', 'hi', 'hey', 'hujambo', 'habari', 'jambo', 'salamu',
      'mambo', 'good morning', 'good evening', 'asante', 'karibu'],
  },
];

// Scaffolding that carries no topic: question openers, politeness, and the app's
// own name. Removed before matching so "How do I advertise my store?" matches on
// `advertis` and not on `how do i`.
const FILLER = [
  'how do i', 'how can i', 'how to', 'can you', 'could you', 'please', 'help me',
  'i want to', 'i need to', 'i would like to', 'what is', 'what are', 'what s',
  'where can i', 'when can i', 'why', 'tell me', 'explain', 'advice', 'tips',
  'nini', 'vipi', 'nini naweza', 'naomba', 'nisaidie', 'msaada', 'wapi naweza',
  'linapoweza', 'kwa nini', 'niambie', 'eleza', 'ushauri', 'mawazo',
  'soko vibe ai', 'soko vibe', 'you', 'the', 'a', 'an', 'my', 'i', 'me', 'is',
  'for', 'to', 'of', 'and', 'do', 'does', 'can', 'should', 'any', 'some',
  'hi', 'hello', 'hey', 'asante', 'karibu', 'jambo', 'habari', 'salamu', 'mambo',
];

const SWAHILI_MARKERS = /\b(na|ya|kwa|ni|wa|za|la|cha|vya|katika|kwamba|zake|moja| hizo| hizo| kama| kwenye| ili| wakati| sana| zaidi| ndani| nini| vipi| wapi| lini| wengine| nyingi| hakuna| kuna)\b/;
const ENGLISH_MARKERS = /\b(the|and|for|you|with|that|this|how|what|where|can|would|should|from|about|your|please|need|want|best|good)\b/i;

/**
 * Picks the display language for a title from the message itself.
 *
 * Guessing from the app locale would mislabel every Swahili question asked by an
 * English-locale user, which is common on this marketplace — the app language and
 * the language someone types in are not the same thing.
 */
function detectLanguage(text) {
  const sw = (String(text).match(SWAHILI_MARKERS) || []).length;
  const en = (String(text).match(ENGLISH_MARKERS) || []).length;
  if (sw > en) return 'sw';
  if (en > sw) return 'en';
  return null;
}

/**
 * Builds a conversation title from the first useful user message.
 *
 * @param {string} message raw user text
 * @returns {string} a title safe to render in a list — never empty
 */
function generateTitle(message) {
  const raw = String(message || '').trim();
  if (!raw) return 'New Chat';

  const language = detectLanguage(raw);
  const lowered = raw.toLowerCase();

  for (const topic of TOPICS) {
    if (topic.words.some((w) => lowered.includes(w))) {
      return language === 'sw' && topic.labelSw ? topic.labelSw : topic.label;
    }
  }

  const fragment = significantWords(raw);
  if (!fragment.length) return language === 'sw' ? 'Mazungumzo' : 'Conversation';
  return titleCase(fragment.join(' '));
}

/**
 * The message's content words, with scaffolding removed.
 *
 * Stops at the first filler token rather than skipping past it: in a sentence like
 * "advertising tips for my shop I need pricing" the tail after `i` is a second
 * question, and gluing it on would produce "Advertising Pricing", which reads as
 * two unrelated topics in a 60-character list row.
 */
function significantWords(raw) {
  const words = raw
    .replace(/[^\p{L}\p{N}\s'-]/gu, ' ')
    .split(/\s+/)
    .filter(Boolean);

  const kept = [];
  for (const word of words) {
    const lower = word.toLowerCase();
    if (FILLER.includes(lower)) break;
    if (word.length < 3) continue;
    kept.push(word);
    if (kept.length >= MAX_TITLE_WORDS) break;
  }
  return kept;
}

function titleCase(text) {
  const trimmed = text.length <= MAX_TITLE_CHARS ? text : `${text.slice(0, MAX_TITLE_CHARS - 1)}…`;
  return trimmed.charAt(0).toUpperCase() + trimmed.slice(1);
}

/**
 * Whether a message is worth titling from.
 *
 * A bare greeting ("hi", "mambo") is not a topic, so titling the conversation from
 * it would permanently label a real thread "Salamu". The first message that
 * carries actual content is the one that names the conversation.
 */
function isUsefulFirstMessage(message) {
  const raw = String(message || '').trim();
  if (raw.length < 8) return false;
  const only = raw
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter(Boolean);
  if (only.length < 2) return false;
  return !TOPICS.some((t) => t.label === 'Greetings' && t.words.some((w) => raw.toLowerCase() === w));
}

module.exports = { generateTitle, isUsefulFirstMessage, detectLanguage, TOPICS };