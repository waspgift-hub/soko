# Soko Vibe Finance & Payment Architecture

## 1. Authoritative Source of Truth
Soko Vibe uses a hybrid database architecture to balance transactional state and financial auditing.

### The Golden Rule
**Money lives in Firestore.** 
Any change to a user's balance, an escrow hold, or a payout MUST be recorded in the Firestore Ledger via `services/commerce-store.js`. Postgres records are for lifecycle state; Firestore records are for value.

| Entity | Primary Store | Role |
| :--- | :--- | :--- |
| **Order State** | Postgres | Lifecycle (Pending $\rightarrow$ Paid $\rightarrow$ Delivered) |
| **Payment Event** | Postgres | Interaction with ClickPesa, idempotency keys |
| **Wallet Balance** | Firestore | Authoritative current balance |
| **Ledger Entry** | Firestore | Immutable audit trail of every cent moved |
| **Escrow Hold** | Firestore | Value locked during order lifecycle |

---

## 2. Payment Lifecycle (The Flow)

### A. Collection (Buyer $\rightarrow$ Platform)
1. `OrderController` $\rightarrow$ `PaymentService` (Postgres): Initiates ClickPesa USSD push.
2. Order state $\rightarrow$ `PAYMENT_PENDING`.
3. ClickPesa Webhook $\rightarrow$ `PaymentService` (Postgres): Verifies payment.
4. `PaymentService` $\rightarrow$ `CommerceStore` (Firestore): Creates an **Escrow Hold**.
5. Order state $\rightarrow$ `ESCROW_HELD`.

### B. Settlement (Platform $\rightarrow$ Seller)
1. Buyer confirms delivery (via OTP) $\rightarrow$ `HandoverService`.
2. `HandoverService` $\rightarrow$ `CommerceStore` (Firestore):
   - Debits **Escrow Hold**.
   - Credits **Seller Wallet**.
   - Records `SETTLEMENT` ledger entry.
3. Order state $\rightarrow$ `COMPLETED`.

### C. Payout (Platform $\rightarrow$ Seller's Bank/Mobile Money)
1. Seller requests withdrawal $\rightarrow$ `WalletService` (Firestore).
2. `WalletService`:
   - Atomic Transaction: Debits **Wallet Balance** + Creates `RESERVED` ledger entry.
3. `FinanceJob` (BullMQ) $\rightarrow$ ClickPesa API: Executes Payout.
4. ClickPesa Confirmation $\rightarrow$ `WalletService`: Updates status to `COMPLETED`.

---

## 3. Safety & Reliability Guards

### Idempotency
All financial POSTs use a deterministic `Idempotency-Key` (e.g., `settlement_{orderId}`). The system uses:
- Redis SETNX locks for coordination.
- Database UNIQUE constraints for hard enforcement.
- State-priority checks (terminal states are no-ops).

### RBAC & Security
- **Client-Side**: Firestore Rules prevent any client-side update to `walletBalance`, `isAdmin`, or `trust` fields.
- **Server-Side**: Only the Admin SDK (server) can mutate financial records.

### Reconciliation
A background `FinanceJob` polls the ClickPesa API and the Postgres `Payment` table to ensure no payments are "stranded" (e.g., paid at gateway but not credited in Firestore).
