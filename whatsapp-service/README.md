# WhatsApp Service

Small Express API that sends WhatsApp messages through the Meta WhatsApp Cloud API.
Other parts of your system call it over HTTP, so they never handle the access token.

## Install

Requires Node.js 20 or newer.

```bash
cd whatsapp-service
npm install
cp .env.example .env     # Windows PowerShell: copy .env.example .env
```

Edit `.env` and set:

- `USER_ACCESS_TOKEN`: your access token from Meta. Keep it only in `.env`.
- `API_KEY`: a long random string. Your other systems send it in the `x-api-key` header.

## Run

```bash
npm start        # production-style
npm run dev      # restarts on file changes
npm test         # unit tests, no network calls
```

## Endpoints

All `/api` routes need `x-api-key: <API_KEY>` when `API_KEY` is set.

### GET /api/status

Checks the token against Meta.

```bash
curl -H "x-api-key: $API_KEY" http://localhost:3000/api/status
```

`token` is `valid`, `invalid` (expired or wrong token), `missing`, or `unknown` (Meta unreachable).

### POST /api/send-message

```bash
curl -X POST http://localhost:3000/api/send-message \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"to": "+255693273241", "message": "Habari! Oda yako imethibitishwa."}'
```

Success:

```json
{ "success": true, "to": "255693273241", "wamid": "wamid.HBgM...", "waId": "255693273241" }
```

Failure returns `success: false`, a `code`, and the Meta `graphCode` when there is one.

### POST /api/send-bulk

```bash
curl -X POST http://localhost:3000/api/send-bulk \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"recipients": ["+255693273241", "0712345678"], "message": "Asante kwa kuagiza!"}'
```

Response:

```json
{
  "success": true,
  "total": 2,
  "duplicatesRemoved": 0,
  "sent": 1,
  "failed": 1,
  "results": [
    { "to": "255693273241", "ok": true, "wamid": "wamid.HBgM..." },
    { "to": "255712345678", "ok": false, "code": "RECIPIENT_NOT_ON_WHATSAPP", "error": "..." }
  ]
}
```

Limits: `BULK_MAX_RECIPIENTS` per request (default 500), sent `BULK_CONCURRENCY` at a time (default 5), duplicates removed.

## Error codes

| code | Meaning | What to do |
|---|---|---|
| `TOKEN_INVALID_OR_EXPIRED` | Token expired or wrong | Generate a new token in Meta and update `.env` |
| `RATE_LIMITED` | Meta or this API is throttling | Wait and retry. Transient errors are already retried 3 times |
| `INVALID_PHONE` | Number cannot be normalized | Send a Tanzanian-style number such as `+255...` or `0...` |
| `RECIPIENT_NOT_ALLOWED` | Test mode: number not in the allowed list | Add the number in the Meta dashboard |
| `RECIPIENT_NOT_ON_WHATSAPP` | Number has no WhatsApp | Skip or ask the customer another way |
| `OUTSIDE_24H_WINDOW` | Free text only works within 24h of a customer message | Use an approved **template** message |
| `NOT_CONFIGURED` | `.env` missing token or phone number ID | Fill in `.env` and restart |
| `UNAUTHORIZED` | Missing or wrong `x-api-key` | Send the correct header |

## Important limits from Meta

- Free-text messages work only inside the **24-hour customer service window**, which opens when the customer messages you. For automatic messages to customers who have not written to you recently, you must use **approved message templates**. Text-only bulk sending will fail for those customers with `OUTSIDE_24H_WINDOW`.
- While the number is in test mode, Meta only delivers to numbers you added as test recipients.

## Logs

Every attempt is appended to `logs/messages.log` as one JSON line:

```json
{"ts":"2026-11-02T11:30:00.000Z","source":"send-message","to":"********3241","ok":true,"wamid":"wamid.HBgM...","errorCode":null,"bodyLength":26}
```

Phone numbers are masked and the message text is not stored, only its length.

## Security notes

- Never commit `.env`. It is in `.gitignore`.
- Set `API_KEY`. Without it, anyone who can reach the port can send messages from your number.
- Run it behind HTTPS in production. Rate limits are set by `RATE_LIMIT_PER_MINUTE`.
