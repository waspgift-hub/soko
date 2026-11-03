# Production Payment Webhook System

A horizontally-scalable payment webhook processor built with Node.js, Express, BullMQ, and Redis — designed for deployment on Render.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │        Payment Gateway              │
                    │   (Stripe, Paystack, etc.)          │
                    └──────────────┬──────────────────────┘
                                   │ POST /webhook/payment
                                   ▼
                    ┌──────────────────────────────────────┐
                    │   Render Load Balancer               │
                    │   (distributes across instances)     │
                    └──┬───────────────────────────────┬──┘
                       │                               │
              ┌────────▼────────┐             ┌────────▼────────┐
              │  API Instance 1 │             │  API Instance N │
              │  (Express)      │             │  (Express)      │
              │                 │             │                 │
              │ 1. HMAC verify  │             │ 1. HMAC verify  │
              │ 2. SETNX lock ──┼──────┐      │ 2. SETNX lock   │
              │ 3. Queue.add  ──┼──┐   │      │ 3. Queue.add   │
              │ 4. Return 200   │  │   │      │ 4. Return 200   │
              └─────────────────┘  │   │      └─────────────────┘
                                   │   │
                          ┌────────▼───▼────────┐
                          │   Redis (Managed)   │
                          │                     │
                          │ • Idempotency locks │
                          │ • BullMQ job queue  │
                          │ • Job state cache   │
                          └────────┬────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  Worker Instance 1          │
                    │  (BullMQ Worker)            │
                    │                             │
                    │  1. Dequeue job             │
                    │  2. Manual retry (3x)       │
                    │  3. Prisma $transaction     │
                    │  4. Audit log insert        │
                    │  5. Job complete            │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────▼───────────────┐
                    │  PostgreSQL (Managed)        │
                    │                             │
                    │  • Payment (unique txnId)    │
                    │  • PaymentAuditLog          │
                    └─────────────────────────────┘
```

## Key Design Decisions

### 1. Why separate API and Worker?

| Problem | Solution |
|---------|----------|
| Payment gateways timeout after 5-10s | API returns 200 in <100ms, processes async |
| Database slow during peak traffic | Worker processes at own pace with retries |
| Worker crash = API downtime | Separate processes, independent restarts |
| Can't scale HTTP and DB work independently | Different Render service types |

### 2. How does the idempotency lock prevent race conditions?

```
Timeline (2 Render instances receive same webhook):

Instance A                    Redis                     Instance B
    │                           │                           │
    ├── SETNX lock:txn_abc ────►│                           │
    │◄── OK (lock acquired) ────┤                           │
    │                           │◄── SETNX lock:txn_abc ───┤
    │                           │──── NULL (lock exists) ──►│
    ├── Queue.add(job) ────────►│                      Rejects (200 OK)
    ├── Release lock ──────────►│                           │
    │                           │                           │
    └── Return 200 ─────────────► Gateway happy              │
```

**Why this works:**
- Redis `SETNX` is atomic — only one client wins
- TTL (30s) prevents deadlock if a instance crashes
- No distributed locks needed in the database

### 3. How does retry with exponential backoff work?

```
Job attempt timeline:

Attempt 1: DB connection timeout → retry in 1s
Attempt 2: DB connection timeout → retry in 2s
Attempt 3: DB connection timeout → retry in 4s
Attempt 4: DB connection timeout → throw error
           → BullMQ marks job as "failed"
           → Available in Bull Board for manual inspection
```

**Two layers of retry:**
1. **Manual retry** (within worker): Handles transient DB errors (connection timeout, pool exhaustion)
2. **BullMQ retry** (queue-level): Re-queues the entire job if manual retry fails

### 4. How does the system prevent double spending?

| Layer | Mechanism |
|-------|-----------|
| API server | Redis `SETNX` idempotency lock |
| BullMQ | Job ID deduplication (`payment:{txn_id}`) |
| Database | Unique constraint on `transactionId` |
| Worker | Status priority check (can't downgrade completed→pending) |

## Project Structure

```
payment-system/
├── render.yaml              # Render Blueprint (deploy all services)
├── package.json
├── .env.example
├── prisma/
│   └── schema.prisma        # Database schema with indexes
└── src/
    ├── shared/               # Shared between API and Worker
    │   ├── index.js
    │   ├── redis.js          # ioredis singleton (connection reuse)
    │   ├── queue.js          # BullMQ queue configuration
    │   ├── idempotency.js    # Distributed lock via Redis SETNX
    │   └── logger.js         # Pino structured JSON logger
    ├── api/                  # Server 1: Webhook API
    │   ├── server.js         # Express app + graceful shutdown
    │   └── webhook-verify.js # HMAC-SHA256 signature verification
    └── worker/               # Server 2: Background Worker
        ├── server.js         # BullMQ Worker + event handlers
        ├── payment-processor.js  # Database writes with Prisma
        └── prisma-client.js  # Prisma singleton (connection pool)
```

## Setup

```bash
# 1. Install dependencies
npm install

# 2. Generate Prisma client
npx prisma generate

# 3. Push schema to database
npx prisma db push

# 4. Start API server (terminal 1)
npm run api:dev

# 5. Start worker (terminal 2)
npm run worker:dev
```

## Deploy to Render

```bash
# Option A: Blueprint (recommended)
# 1. Push repo to GitHub
# 2. render.com → New → Blueprint → Select repo
# 3. Set WEBHOOK_SECRET in Render Dashboard

# Option B: CLI
render Blueprints apply render.yaml
```

## Testing the Webhook

```bash
# Simulate a payment webhook
curl -X POST http://localhost:10000/webhook/payment \
  -H "Content-Type: application/json" \
  -d '{
    "transaction_id": "txn_abc123",
    "status": "completed",
    "amount": 99.99,
    "currency": "USD",
    "payer_id": "user_123",
    "payer_email": "customer@example.com",
    "gateway_ref": "gw_ref_xyz"
  }'
```

## Response Time Benchmarks

| Step | Time |
|------|------|
| Express JSON parsing | ~2ms |
| HMAC verification | ~1ms |
| Redis SETNX lock | ~3ms |
| BullMQ queue.add | ~5ms |
| Response serialization | ~1ms |
| **Total** | **~12ms** |

The payment gateway receives a `200 OK` in under 100ms, preventing retries.

## Monitoring

- **Bull Board**: Add `@bull-board/express` for a web dashboard
- **Render Logs**: Structured JSON logs in Render Dashboard
- **Audit Trail**: `PaymentAuditLog` table tracks every state transition

## License

MIT
