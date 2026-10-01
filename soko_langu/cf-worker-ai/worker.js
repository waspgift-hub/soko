// Soko Vibe — Cloudflare Workers AI edge for the AI assistant.
//
// Why this exists: the Node server on Render holds a provider registry with
// failover, and this Worker is one of those providers. Keeping the Workers AI
// call at the edge means the Cloudflare credential never has to exist on
// Render — only a shared key that authenticates Render to this Worker.
//
// The contract with the Node side is deliberately narrow: this Worker speaks
// OpenAI Chat Completions in and OpenAI Chat Completions out. That is what lets
// it sit in the existing provider chain with no change to tool-loop.js, to the
// Flutter client, or to the failover logic.
//
// Three things this Worker must do that a straight pass-through cannot, because
// Workers AI is stricter than the OpenAI-compatible APIs:
//
//   1. Sanitize messages. `content` is REQUIRED and must be a string on the
//      Messages variant — `content: null` and the `[{type:'text',...}]` array
//      shape both fail validation with error 5006 "Bad input".
//   2. Give the model a tool-call contract. gpt-oss on this binding answers
//      with bare JSON in `content` and an empty `tool_calls` array unless the
//      system prompt states the contract explicitly. Measured on
//      @cf/openai/gpt-oss-20b with the Soko Vibe tool prelude: without the
//      contract, `tool_calls: []` and `content: '{"q":"phone 500000 Tsh"}'`;
//      with it, `finish_reason: "tool_calls"` and a real tool call. The Node
//      tool loop keys on `message.tool_calls`, so without this the user would
//      see raw JSON in the chat bubble.
//   3. Never let a null content reach the client. gpt-oss is a reasoning model:
//      a budget below its reasoning appetite returns `content: null` with the
//      answer parked in `reasoning_content`, and the Flutter client renders
//      `content.toString()`, which would show the user the literal text "null".
//
// Auth: `X-AI-Key` must equal the AI_EDGE_KEY secret. This endpoint is
// server-to-server only; the Flutter app never calls it directly, it calls
// /api/ai/chat on the API host, which authenticates the Firebase token and rate
// limits per IP before any provider is called.

/**
 * Client model id -> Workers AI model.
 *
 * The Flutter client hardcodes Groq model ids (groq_service.dart) and knows
 * nothing about Cloudflare. Mapping them here means switching which provider
 * answers a request changes nothing a user can observe, and no app release.
 *
 * gpt-oss is the same weight family Groq serves, so a failover lands on
 * equivalent quality rather than a downgrade.
 */
const DEFAULT_MODEL_MAP = {
  'openai/gpt-oss-120b': '@cf/openai/gpt-oss-120b',
  'openai/gpt-oss-20b': '@cf/openai/gpt-oss-20b',
};

const DEFAULT_TEXT_MODEL = '@cf/openai/gpt-oss-120b';
const DEFAULT_LITE_MODEL = '@cf/meta/llama-3.2-3b-instruct';
const DEFAULT_WHISPER_MODEL = '@cf/openai/whisper-large-v3-turbo';

// A reasoning model needs headroom before it emits anything usable. Measured on
// @cf/openai/gpt-oss-20b with max_tokens=60: 60 completion tokens of
// `reasoning_content`, `content: null`, `finish_reason: "length"` — i.e. the
// entire budget spent thinking and nothing said. Below this budget the request
// goes to a non-reasoning model instead of returning an empty answer. Mirrors
// the same threshold the Gemini provider applies.
const MIN_TOKENS_FOR_REASONING = 512;

// Guards on a request that passed a 10MB body limit with no per-field
// validation upstream. 413 is deliberately NOT failover-worthy, so an oversized
// request fails fast on every provider instead of being retried three times.
const MAX_MESSAGES = 60;
const MAX_TOTAL_CHARS = 120_000;
const MAX_AUDIO_BYTES = 8 * 1024 * 1024;

const TOOL_CONTRACT = [
  '',
  'Tool call contract (overrides any other output format instruction):',
  'To call a tool, reply with ONLY a JSON object and nothing else:',
  '{"name":"<exact tool name>","arguments":{...}}',
  'No prose, no markdown, no code fences. If a tool result is in the next message, answer the user in prose.',
].join('\n');

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return Response.json({
        ok: true,
        service: 'soko-ai-edge',
        models: modelMap(env),
        text: textModel(env),
        lite: liteModel(env),
        whisper: whisperModel(env),
      });
    }

    if (!authorized(request, env)) {
      return Response.json({ error: { message: 'Unauthorized', type: 'authentication_error' } }, { status: 401 });
    }

    if (url.pathname === '/chat' && request.method === 'POST') return handleChat(request, env);
    if (url.pathname === '/transcribe' && request.method === 'POST') return handleTranscribe(request, env);

    return Response.json({ error: { message: `No route for ${request.method} ${url.pathname}`, type: 'not_found' } }, { status: 404 });
  },
};

function authorized(request, env) {
  const expected = env.AI_EDGE_KEY;
  // Fail closed: an unconfigured secret must not mean an open endpoint, because
  // "forgot to set the key" would otherwise become a public, billable LLM.
  if (!expected) return false;
  const presented = request.headers.get('x-ai-key') || '';
  if (presented.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < presented.length; i++) diff |= presented.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

function modelMap(env) {
  const extra = parseMap(env.AI_MODEL_MAP);
  return { ...DEFAULT_MODEL_MAP, ...extra };
}

function parseMap(raw) {
  if (!raw) return {};
  const out = {};
  for (const pair of String(raw).split(',')) {
    const [from, to] = pair.split('=').map((s) => s && s.trim());
    if (from && to) out[from] = to;
  }
  return out;
}

function textModel(env) {
  return env.AI_MODEL || DEFAULT_TEXT_MODEL;
}

function liteModel(env) {
  return env.AI_MODEL_LITE || DEFAULT_LITE_MODEL;
}

function whisperModel(env) {
  return env.AI_MODEL_WHISPER || DEFAULT_WHISPER_MODEL;
}

/**
 * Picks the Workers AI model for a request.
 *
 * Unknown ids (a newer app build, a hand-rolled request) fall through to the
 * default rather than being forwarded verbatim: Workers AI rejects an unknown
 * model with a 404-ish error, and 4xx is not failover-worthy, so forwarding it
 * would surface as a hard failure instead of an answer.
 */
function resolveModel(env, requested, maxTokens) {
  if (typeof maxTokens === 'number' && maxTokens > 0 && maxTokens < MIN_TOKENS_FOR_REASONING) {
    return liteModel(env);
  }
  return modelMap(env)[requested] || textModel(env);
}

function flattenContent(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    // The image_url part of the OpenAI shape is dropped rather than rendered as
    // a data URL: it is megabytes of base64 the model cannot read, and
    // forwarding it would blow the character guard on a legitimate request.
    return content
      .filter((p) => p && (p.type === 'text' || typeof p.text === 'string'))
      .map((p) => (typeof p.text === 'string' ? p.text : ''))
      .filter(Boolean)
      .join('\n');
  }
  if (content == null) return '';
  return String(content);
}

/**
 * Renders an assistant turn's tool calls as the contract JSON, which is what
 * the model's own content was before it was promoted to a `tool_calls` array.
 * The Node tool loop replays the assistant turn verbatim on the next round, and
 * `content` is required, so this text is what tells the model what it asked for.
 */
function toolCallsToContent(calls) {
  if (!Array.isArray(calls) || !calls.length) return '';
  return calls
    .map((c) => {
      const name = c?.function?.name;
      if (!name) return '';
      let args = c?.function?.arguments;
      if (typeof args !== 'string') {
        try {
          args = JSON.stringify(args || {});
        } catch {
          args = '{}';
        }
      }
      return JSON.stringify({ name, arguments: args });
    })
    .filter(Boolean)
    .join('\n');
}

function sanitizeMessages(messages) {
  return messages.map((m) => {
    const role = m?.role === 'assistant' || m?.role === 'system' ? m.role : 'user';
    const calls = m?.tool_calls;
    const content = flattenContent(m?.content) || (role === 'assistant' ? toolCallsToContent(calls) : '');
    return { role, content };
  });
}

function toolNames(tools) {
  if (!Array.isArray(tools)) return [];
  return tools
    .map((t) => t?.function?.name || t?.name)
    .filter((n) => typeof n === 'string' && n);
}

/**
 * Promotes a bare JSON tool call out of `content` and into `tool_calls`.
 *
 * Only fires when the parsed object names one of the tools actually supplied
 * with this request. That guard is the whole point: a genuine prose answer does
 * not parse as `{"name":"search_products",...}`, so a false positive here would
 * need the model to both emit valid JSON and pick a real tool name by accident.
 * Anything that does not match is left as content for the caller to read.
 */
function promoteInlineToolCall(message, names) {
  if (!names.length) return message;
  const raw = typeof message.content === 'string' ? message.content.trim() : '';
  if (!raw.startsWith('{')) return message;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return message;
  }
  const name = parsed?.name || parsed?.function?.name;
  if (!name || !names.includes(name)) return message;
  const args = parsed.arguments ?? parsed.function?.arguments ?? {};
  return {
    ...message,
    content: '',
    tool_calls: [
      {
        id: `call_${name}_${Date.now().toString(36)}`,
        type: 'function',
        function: { name, arguments: typeof args === 'string' ? args : JSON.stringify(args) },
      },
    ],
  };
}

function withToolContract(messages) {
  const out = messages.slice();
  const idx = out.findIndex((m) => m.role === 'system');
  const contract = { role: 'system', content: TOOL_CONTRACT.trim() };
  if (idx === -1) out.unshift(contract);
  else {
    out[idx] = { role: 'system', content: `${out[idx].content}\n${contract.content}` };
  }
  return out;
}

async function handleChat(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return badRequest('Request body must be JSON');
  }

  const raw = Array.isArray(body?.messages) ? body.messages : [];
  if (!raw.length) return badRequest('messages[] required');

  if (raw.length > MAX_MESSAGES) {
    return Response.json(
      { error: { message: `Too many messages (${raw.length} > ${MAX_MESSAGES})`, type: 'invalid_request_error' } },
      { status: 413 },
    );
  }

  const maxTokens = Number.isFinite(body.max_tokens) ? body.max_tokens : undefined;
  let messages = sanitizeMessages(raw);
  const chars = messages.reduce((sum, m) => sum + m.content.length, 0);
  if (chars > MAX_TOTAL_CHARS) {
    return Response.json(
      { error: { message: `Prompt too large (${chars} > ${MAX_TOTAL_CHARS} characters)`, type: 'invalid_request_error' } },
      { status: 413 },
    );
  }

  const tools = Array.isArray(body.tools) && body.tools.length ? body.tools : null;
  const names = toolNames(tools);
  if (tools) messages = withToolContract(messages);

  const model = resolveModel(env, body.model, maxTokens);
  const input = { messages, stream: false };
  if (tools) input.tools = tools;
  if (typeof maxTokens === 'number') input.max_tokens = maxTokens;
  else input.max_tokens = 1024;
  if (typeof body.temperature === 'number') input.temperature = body.temperature;
  if (typeof body.top_p === 'number') input.top_p = body.top_p;

  const run = await runModel(env, model, input);
  if (run.error) return run.error;
  const out = run.value;
  let message = out?.choices?.[0]?.message || {};

  if (tools) message = promoteInlineToolCall(message, names);

  // Reasoning models park the answer in reasoning_content when the budget runs
  // out mid-thought, and `content: null` would reach the client as the string
  // "null". Serving the reasoning text is better than serving nothing.
  if (!message.content && message.reasoning_content) {
    message = { ...message, content: message.reasoning_content };
  }

  const choice = {
    index: 0,
    message: {
      role: 'assistant',
      content: message.content ?? '',
      ...(message.tool_calls?.length ? { tool_calls: message.tool_calls } : {}),
    },
    finish_reason: out?.choices?.[0]?.finish_reason || 'stop',
  };

  // Envelope is rebuilt rather than forwarded: the client parses
  // choices[0].message.content, and the raw Workers AI response carries extra
  // fields (token_ids, kv_transfer_params) that are noise on the wire.
  return Response.json({
    id: out?.id || `chatcmpl-${Date.now().toString(36)}`,
    object: 'chat.completion',
    created: out?.created || Math.floor(Date.now() / 1000),
    model,
    choices: [choice],
    usage: out?.usage || null,
  });
}

async function handleTranscribe(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return badRequest('Request body must be JSON');
  }

  const audio = body?.audio;
  if (typeof audio !== 'string' || !audio.length) return badRequest('audio (base64) required');
  if (audio.length > MAX_AUDIO_BYTES) {
    return Response.json(
      { error: { message: 'Audio too large', type: 'invalid_request_error' } },
      { status: 413 },
    );
  }

  const input = { audio };
  if (body.language) input.language = body.language;
  if (typeof body.vad_filter === 'boolean') input.vad_filter = body.vad_filter;

  const model = whisperModel(env);
  const run = await runModel(env, model, input);
  if (run.error) return run.error;
  return Response.json(run.value?.result || { text: '' });
}

/**
 * Runs a model and normalizes a throw into a status the Node gateway can act on.
 *
 * Without this, a Workers AI failure surfaces as an opaque 500 with a stack
 * trace in the body, and the gateway cannot tell "the model rejected this
 * request" (400, do not retry) from "Workers AI is degraded" (502, fail over).
 */
async function runModel(env, model, input) {
  try {
    return { value: await env.AI.run(model, input) };
  } catch (err) {
    return { error: errorResponse(err) };
  }
}

function badRequest(message) {
  return Response.json({ error: { message, type: 'invalid_request_error' } }, { status: 400 });
}

/**
 * Turns a thrown error into a body the Node provider can reason about.
 *
 * The status matters: the gateway fails over on 429/5xx/timeout and does NOT
 * fail over on an ordinary 4xx, so a genuine bad request must not be reported
 * as a 5xx and sent round the whole provider chain.
 */
function errorResponse(err) {
  const message = err?.message || 'Workers AI error';
  if (/bad input|oneOf at|validation/i.test(message)) {
    return Response.json({ error: { message, type: 'invalid_request_error' } }, { status: 400 });
  }
  if (/rate limit|too many requests|429/i.test(message)) {
    return Response.json({ error: { message, type: 'rate_limit_error' } }, { status: 429 });
  }
  return Response.json({ error: { message, type: 'server_error' } }, { status: 502 });
}
