# soko-ai-edge — Cloudflare Workers AI provider

Internal LLM/Whisper endpoint for the Soko Vibe AI assistant. The Node server
(`../server`) calls it as one entry in its provider chain
(`../server/src/modules/ai/ai-gateway.js`); the Flutter app never sees it.

```
Flutter ──▶ /api/ai/chat  ──▶ Node gateway ──▶ groq      (primary)
             (Firebase auth,  ──▶ gemini    (fallback)
              rate limit,      ──▶ this Worker (last resort, chat + Whisper)
              tool loop)               └─▶ Workers AI
```

## Why a Worker instead of a Cloudflare API call from Node

The Workers AI binding (`env.AI.run`) is the supported way to call the models,
and it needs the call to originate on Cloudflare. That means the inference code
has to run at the edge — so the only thing left to run on Render is a thin
proxy. What that buys:

- The Cloudflare API credential never exists on Render. Only a shared key does.
- Model calls skip a Cloudflare API hop, and the model catalogue can be changed
  in `wrangler.toml` without a server deploy.
- If Groq's free tier is exhausted, the assistant keeps working. This Worker is
  the difference between "the AI button shows an error" and "the AI button is
  slightly slower".

The shared key is a real boundary, so treat it like a password: it is a Worker
secret, never a var and never in git.

## Endpoints

| Method | Path          | Auth       | Purpose                                        |
| ------ | ------------- | ---------- | ---------------------------------------------- |
| GET    | `/health`     | none       | liveness + which models are in use             |
| POST   | `/chat`       | `X-AI-Key` | OpenAI Chat Completions in, OpenAI out         |
| POST   | `/transcribe` | `X-AI-Key` | `{ audio }` base64 in, `{ text }` out          |

`/health` is deliberately unauthenticated: it is what `wrangler` and uptime
checks hit, and it returns no secrets — only model ids.

## The three Workers AI differences worth knowing

Everything below is measured behaviour on this binding, not theory. It is the
reason this file exists instead of a one-line `env.AI.run` passthrough.

**1. `content` is required and must be a string.** The Messages variant rejects
`content: null` and the OpenAI `[{type:'text'},{...}]` array shape with error
`5006: AiError: Bad input ... Type mismatch of '/messages/0/content'`. The Node
tool loop replays assistant turns as `content: null` whenever the model made a
tool call, so without `sanitizeMessages` every tool-using request would fail.
Arrays are flattened to their text parts, which is also what silently drops
`image_url` parts — see the vision note below.

**2. gpt-oss needs an explicit tool-call contract.** With only the app's own
tool prelude, `@cf/openai/gpt-oss-20b` answers by putting the arguments in
`content` and returning `tool_calls: []`:

```
content: '{"q":"phone 500000 Tsh","max":10}'   tool_calls: []   finish_reason: "stop"
```

`tool-loop.js` keys on `message.tool_calls`, so the user would read raw JSON in
the chat bubble and no product search would ever run. `TOOL_CONTRACT` states the
output format explicitly, after which the same request returns
`finish_reason: "tool_calls"` with a real call, and a following round with tool
results comes back as Swahili prose. `promoteInlineToolCall` is the safety net
for when a model ignores the contract, and it only fires if the JSON names one
of the tools actually passed with the request.

**3. A reasoning model can return `content: null`.** gpt-oss spends its budget
on `reasoning_content` first. At `max_tokens: 60` the whole budget went to
reasoning, `content` was `null`, and the client renders
`content.toString()` — the user would see the literal word "null". Two defences:
requests under `MIN_TOKENS_FOR_REASONING` go to a non-reasoning model, and
`reasoning_content` is used as the answer if `content` is still empty.

**Vision.** The Workers AI vision models take one flattened prompt string, not
the content array `identifyImage` sends, so the Cloudflare provider declares
`supportsModel('llama-3.2-90b-vision-preview') === false` and the gateway skips
it. Image identification stays on Gemini, unchanged.

## Deploy

```bash
cd soko_langu/cf-worker-ai
npx wrangler login
npx wrangler deploy

# Shared key. Same value goes into the server's CF_AI_KEY.
npx wrangler secret put AI_EDGE_KEY
```

`wrangler.toml` has no `[[routes]]`, so the Worker is reachable only on its
`workers.dev` hostname. Keep it that way while the endpoint is billable: there is
no DNS record pointing a scanner at it, and the shared key is the only thing
between the internet and a paid inference API.

If the account has never been billed for Workers AI, enable it once at
https://dash.cloudflare.com → Workers AI before the first call.

## Smoke test

```bash
KEY=...   # the AI_EDGE_KEY you just set
URL=https://soko-ai-edge.<subdomain>.workers.dev

curl -s $URL/health

# No key -> 401. A missing secret on the Worker is also 401, it fails closed.
curl -s -o /dev/null -w '%{http_code}\n' -X POST $URL/chat \
  -H 'content-type: application/json' -d '{"messages":[{"role":"user","content":"hi"}]}'

curl -s -X POST $URL/chat \
  -H "x-ai-key: $KEY" -H 'content-type: application/json' \
  -d '{"model":"openai/gpt-oss-120b","max_tokens":400,
       "messages":[{"role":"user","content":"Ndugu yake anaitwa nini?"}]}'
```

Wiring the server side: set `CF_AI_URL` and `CF_AI_KEY` in the Render dashboard,
keep `AI_PROVIDER_ORDER=groq,gemini,cloudflare`, and deploy. To make this the
provider that answers first, set `AI_PROVIDER_ORDER=cloudflare,groq,gemini` —
worth doing only after a live smoke test, since Groq is faster and cheaper at
equal output.
