// Seller wallet service — Firestore implementation (Phase 5).
//
// Previously the money moved through Postgres rows (`wallet`,
// `walletLedgerEntry`, `withdrawal`, `payoutTransaction`). Now the wallet is
// `wallets/{sellerUid}` with an append-only `walletTransactions/{id}` ledger,
// and withdrawals live in `withdrawals/{id}`. The public function names and
// return shapes are unchanged so routes, admin routes, and finance-jobs keep
// their contracts.
const { getFirebaseFirestore } = require('../../config/firebase');
const { resolvePayoutPhone } = require('../../services/payout-phone');
const { requireLock, releaseLock } = require('../../config/redis');
const { getProvider } = require('../payments/provider-factory');
const commerceStore = require('../../services/commerce-store');
const { FieldValue } = require('firebase-admin/firestore');

/**
 * Withdrawal lifecycle.
 *
 *   requested  → the row exists, no money moved
 *   reserved   → balance debited + ledger written (ATOMIC, both or neither)
 *   disbursing → provider payout call in flight (money may or may not have moved)
 *   processing → provider accepted, awaiting confirmation
 *   completed  → provider confirmed the payout
 *   failed     → terminally failed; the reservation is refunded
 *
 * The invariant the previous shape could not hold was "a payout never happens
 * without a matching ledger debit". `reserve` now debits inside the SAME
 * Firestore transaction that writes the ledger entry, and the payout can only
 * start from `reserved`. See requestWithdrawal/processWithdrawal.
 */
const WITHDRAWAL_STATUS = {
  REQUESTED: 'requested',
  RESERVED: 'reserved',
  DISBURSING: 'disbursing',
  PROCESSING: 'processing',
  COMPLETED: 'completed',
  FAILED: 'failed',
};

/** States from which the provider payout may be dispatched for the first time. */
const PAYOUT_RETRYABLE = new Set([
  WITHDRAWAL_STATUS.RESERVED,
]);

/**
 * States the sweeper may re-drive, but only after asking the gateway whether it
 * already has this payout.
 *
 * `disbursing` means "the call was claimed and may or may not have reached
 * ClickPesa". Re-dispatching it blind is how a seller gets paid twice; the
 * gateway is consulted first (see `_gatewayHasPayout`).
 */
const PAYOUT_REVERIFYABLE = new Set([
  WITHDRAWAL_STATUS.DISBURSING,
]);

/**
 * `processing` is deliberately absent from both sets. The gateway accepted the
 * payout and we have its id; the only thing that may move it is a confirmation
 * (provider webhook or `confirmPayout`). Including it in a retryable set — as it
 * was — meant every sweep re-called `initiatePayout` for every in-flight
 * withdrawal.
 */
const PAYOUT_AWAITING_CONFIRMATION = new Set([
  WITHDRAWAL_STATUS.PROCESSING,
]);

/** States that are terminal for the withdrawal and must never be paid again. */
const PAYOUT_TERMINAL = new Set([
  WITHDRAWAL_STATUS.COMPLETED,
  WITHDRAWAL_STATUS.FAILED,
]);

/**
 * Holds the seller's money in one Firestore transaction.
 *
 * Both writes — the wallet balance and the immutable ledger entry — are
 * committed together, so there is no window in which one exists without the
 * other. Idempotent on `withdrawalId`, so a retried request re-returns the same
 * reservation instead of debiting twice.
 */
async function reserveWithdrawalFunds({ db, withdrawalId, sellerId, amount }) {
  const store = db || getFirebaseFirestore();

  return store.runTransaction(async (t) => {
    const wRef = store.collection(commerceStore.COLLECTIONS.wallets).doc(String(sellerId));
    const wSnap = await t.get(wRef);

    const ledgerId = commerceStore.buildLedgerId(`ledger_withdrawal_${withdrawalId}`);
    const ledgerRef = store.collection(commerceStore.COLLECTIONS.ledger).doc(ledgerId);

    // Idempotency: an existing ledger entry means this withdrawal is already
    // reserved. Firestore's optimistic retry means this read is authoritative.
    const ledgerSnap = await t.get(ledgerRef);
    if (ledgerSnap.exists) {
      const existing = wSnap.exists
        ? wSnap.data().availableBalance || 0
        : 0;
      return {
        alreadyReserved: true,
        balanceAfter: commerceStore.tzs(existing),
      };
    }

    const prior = wSnap.exists ? commerceStore.tzs(wSnap.data().availableBalance || 0) : 0;
    const next = commerceStore.applyBalance(prior, -Math.abs(amount));

    if (wSnap.exists) {
      t.update(wRef, {
        availableBalance: next,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      t.set(wRef, {
        availableBalance: next,
        pendingBalance: 0,
        frozenBalance: 0,
        totalEarned: 0,
        totalWithdrawn: 0,
        currency: 'TZS',
        status: 'active',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    t.set(ledgerRef, {
      walletId: String(sellerId),
      type: commerceStore.LEDGER_TYPES.WITHDRAWAL_DEBITED,
      amount: Math.abs(amount),
      balanceAfter: next,
      referenceType: 'withdrawal',
      referenceId: String(withdrawalId),
      idempotencyKey: ledgerId,
      description: 'Seller withdrawal',
      createdAt: FieldValue.serverTimestamp(),
    });

    return { alreadyReserved: false, balanceAfter: next };
  });
}

/**
 * Returns reserved funds when a payout terminally fails, so a seller is not
 * debited for money that never reached them.
 *
 * Idempotent on a separate ledger key (`ledger_withdrawal_refund_{id}`), so a
 * duplicate refund call is a no-op rather than a second credit.
 */
async function releaseWithdrawalReservation({ db, withdrawalId, sellerId, amount }) {
  const store = db || getFirebaseFirestore();
  const seller = String(sellerId);
  const amt = Math.abs(amount);
  const refundLedgerId = commerceStore.buildLedgerId(
    `ledger_withdrawal_refund_${withdrawalId}`,
  );
  const refundRef = store.collection(commerceStore.COLLECTIONS.ledger).doc(refundLedgerId);
  const wRef = store.collection(commerceStore.COLLECTIONS.wallets).doc(seller);

  return store.runTransaction(async (t) => {
    const refundSnap = await t.get(refundRef);
    if (refundSnap.exists) return { alreadyRefunded: true };

    const wSnap = await t.get(wRef);
    if (!wSnap.exists) return { alreadyRefunded: true, missingWallet: true };

    const prior = commerceStore.tzs(wSnap.data().availableBalance || 0);
    const next = prior + amt;

    t.update(wRef, {
      availableBalance: next,
      updatedAt: FieldValue.serverTimestamp(),
    });
    t.set(refundRef, {
      walletId: seller,
      type: commerceStore.LEDGER_TYPES.WITHDRAWAL_REFUNDED,
      amount: amt,
      balanceAfter: next,
      referenceType: 'withdrawal',
      referenceId: String(withdrawalId),
      idempotencyKey: refundLedgerId,
      description: 'Withdrawal refunded — payout failed',
      createdAt: FieldValue.serverTimestamp(),
    });

    return { alreadyRefunded: false, balanceAfter: next };
  });
}

/**
 * Get the seller's wallet (auto-created on first access).
 */
async function getWallet(sellerId) {
  return commerceStore.getWallet(sellerId);
}

/**
 * Alias kept for callers that used the transactional variant; the Firestore
 * wallet is idempotent so there is nothing to coordinate.
 */
async function ensureWallet(sellerId) {
  return commerceStore.getWallet(sellerId);
}

/**
 * Get wallet balances plus a paginated ledger history. Shape matches what the
 * Flutter `WalletDetail.fromApi` parses: `balances.available/pending/frozen/
 * totalEarned/totalWithdrawn` and a `ledger[]`.
 */
async function getWalletDetail(sellerId, { page = 1, limit = 20 } = {}) {
  const wallet = await commerceStore.getWallet(sellerId);
  const { ledger, pagination } = await commerceStore.listLedger(sellerId, { page, limit });
  return {
    wallet,
    balances: {
      available: String(wallet.availableBalance),
      pending: String(wallet.pendingBalance),
      frozen: String(wallet.frozenBalance),
      totalEarned: String(wallet.totalEarned),
      totalWithdrawn: String(wallet.totalWithdrawn),
    },
    ledger,
    pagination,
  };
}

/**
 * Seller requests a withdrawal. Debits the ledger atomically (idempotent on
 * `ledger_withdrawal_{id}`), then returns the withdrawal + freshly serialized
 * wallet.
 */
/**
 * Seller requests a withdrawal.
 *
 * Order of operations matters and is the whole point of the rewrite:
 *
 *   1. create the row in `requested`   (no money has moved)
 *   2. reserve the funds               (wallet debit + ledger entry, ONE transaction)
 *   3. flip the row to `reserved`      (now the payout is allowed to start)
 *
 * If the process dies between 1 and 2 the row is `requested` with no money
 * moved — harmless, and the sweeper can expire it. If it dies between 2 and 3
 * the money is reserved but unpaid, and `processWithdrawal` treats `requested`
 * as retryable. The previous order (row first, then ledger as a separate
 * commit) could leave a `pending` row that `finance.withdrawalProcess` would
 * pay out with no ledger debit at all.
 *
 * The amount is validated and rounded here and never taken from the client as
 * a trusted value; `reserveWithdrawalFunds` re-derives the balance itself.
 */
async function requestWithdrawal({ sellerId, amount, phoneNumber }) {
  // Fail closed: if Redis is unreachable we must not let two concurrent
  // withdrawals both pass the balance check and race into the reserve.
  const lock = await requireLock(`withdraw:${sellerId}`, 60);
  const db = getFirebaseFirestore();

  try {
    const requested = Number(amount);
    if (!Number.isFinite(requested) || requested <= 0) {
      throw httpError(400, 'INVALID_AMOUNT');
    }

    const wallet = await commerceStore.getWallet(sellerId);
    if (wallet.status !== 'active') throw httpError(409, 'WALLET_FROZEN');

    const min = Number(process.env.WITHDRAWAL_MIN) || 0;
    const max = Number(process.env.WITHDRAWAL_MAX) || 5000000;
    if (requested < min) throw httpError(400, `BELOW_MINIMUM:${min}`);
    if (requested > max) throw httpError(400, `ABOVE_MAXIMUM:${max}`);

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const dailyLimit = Number(process.env.DAILY_WITHDRAWAL_LIMIT) || 5000000;
    const todayTotal = await commerceStore.sumWithdrawalsToday(sellerId, today, { db });
    // Reserved-but-unpaid withdrawals still hold the seller's money, so they
    // count against the daily cap too.
    if (todayTotal + requested > dailyLimit) {
      throw httpError(429, 'DAILY_WITHDRAWAL_LIMIT_EXCEEDED');
    }

    const ref = db.collection(commerceStore.COLLECTIONS.withdrawals).doc();
    await ref.set({
      sellerId: String(sellerId),
      amount: Math.round(requested),
      provider: 'clickpesa',
      status: WITHDRAWAL_STATUS.REQUESTED,
      phoneNumber: phoneNumber || null,
      idempotencyKey: `withdrawal_${sellerId}_${ref.id}`,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Throws INSUFFICIENT_FUNDS from inside the transaction, so an
    // over-balance request leaves no row reserved and no ledger entry.
    await reserveWithdrawalFunds({
      db,
      withdrawalId: ref.id,
      sellerId,
      amount: Math.round(requested),
    });

    await ref.update({
      status: WITHDRAWAL_STATUS.RESERVED,
      reservedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const updatedWallet = await commerceStore.getWallet(sellerId);
    const committed = await ref.get();
    return {
      withdrawal: commerceStore.serializeWithdrawal(committed),
      wallet: updatedWallet,
    };
  } finally {
    if (lock.acquired) await releaseLock(`withdraw:${sellerId}`, lock.token);
  }
}

/**
 * Sends the provider payout for a reserved withdrawal.
 *
 * Crash-safety matrix (the reason this is a state machine rather than a
 * read-then-write):
 *
 *   crash BEFORE `disbursing` flip  → row still `reserved`, money still held.
 *                                    Retry is safe and free.
 *   crash AFTER  `disbursing` flip  → we do not know whether the provider got
 *                                    the call. Row stays `disbursing`; the
 *                                    next attempt re-sends with the SAME
 *                                    `orderReference` (`W{id}`), which is the
 *                                    provider-side idempotency key, and
 *                                    reconciliation resolves the outcome.
 *                                    No ledger entry is ever written here.
 *   provider returns 4xx (definitive) → `failed` + the reservation is refunded,
 *                                    so the seller keeps their balance.
 *   provider times out / 5xx          → left `disbursing` for retry; NOT
 *                                    refunded, because the payout may still
 *                                    land.
 *
 * The money-moving part (`reserveWithdrawalFunds`) happened in
 * `requestWithdrawal`, so there is no window in which a provider call can be
 * made without a matching ledger debit.
 */
/**
 * Asks the gateway whether it already has a payout for `orderReference`.
 *
 * Returns `{ state: 'seen' | 'absent' | 'unknown' }`. `unknown` is a first-class
 * answer, not an error to swallow: a gateway we could not reach is a gateway we
 * cannot prove has not taken the money, so callers must treat it as "maybe sent".
 *
 * Uses the payout listing endpoint already used by the reconciliation sweep, so
 * this adds no new integration surface.
 */
async function _gatewayHasPayout(orderReference) {
  let rows;
  try {
    // Lazy require: `clickpesa.js` pulls in the axios client and token cache, and
    // wallet-service is imported by many tests that never touch the gateway.
    // eslint-disable-next-line global-require
    const { clickpesaQueryPayouts } = require('../../../clickpesa');
    rows = await clickpesaQueryPayouts({ orderReference });
  } catch (e) {
    console.warn(
      `[wallet] payout lookup failed for ${orderReference}: ${e.message} — treating as unknown`,
    );
    return { state: 'unknown' };
  }

  const list = Array.isArray(rows) ? rows : rows?.data || [];
  const match = (Array.isArray(list) ? list : [])
    .find((r) => String(r?.orderReference || r?.order_reference || r?.reference || '') === orderReference);
  if (!match) return { state: 'absent' };

  return {
    state: 'seen',
    providerPayoutId: match.id || match.payoutId || match.payout_id || null,
    status: match.status || null,
  };
}

async function processWithdrawal({ withdrawalId, executedBy = 'system' }) {
  const lock = await requireLock(`withdraw:${withdrawalId}`, 60);
  const db = getFirebaseFirestore();

  try {
    const ref = db
      .collection(commerceStore.COLLECTIONS.withdrawals)
      .doc(String(withdrawalId));

    const snap = await ref.get();
    if (!snap.exists) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
    const withdrawal = commerceStore.serializeWithdrawal(snap);
    const orderReference = `W${withdrawal.id}`;

    if (PAYOUT_TERMINAL.has(withdrawal.status)) {
      // completed/failed: never pay twice.
      return withdrawal;
    }

    // The gateway already accepted this payout. Re-calling `initiatePayout`
    // here is how a single withdrawal produced two transfers, because the old
    // retryable set contained `processing`. Confirmation is the only thing that
    // may move it forward now.
    if (PAYOUT_AWAITING_CONFIRMATION.has(withdrawal.status)) {
      return withdrawal;
    }

    if (PAYOUT_REVERIFYABLE.has(withdrawal.status)) {
      // `disbursing` is the ambiguous state: a previous attempt may have reached
      // the gateway and died before recording the response. Ask the gateway
      // before touching it. `unknown` (a query failure) is treated as "assume
      // sent" — never as "safe to resend".
      const seen = await _gatewayHasPayout(orderReference);
      if (seen.state === 'seen') {
        await ref.update({
          status: WITHDRAWAL_STATUS.PROCESSING,
          providerPayoutId: seen.providerPayoutId || withdrawal.providerPayoutId || null,
          providerStatus: seen.status || null,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return commerceStore.serializeWithdrawal(await ref.get());
      }
      if (seen.state === 'unknown') {
        // Fail closed: the payout may already be in flight. Flag it for the
        // reconciliation sweep and leave the reservation untouched.
        await ref.update({
          needsManualReview: true,
          needsManualReviewReason: 'gateway_state_unknown',
          updatedAt: FieldValue.serverTimestamp(),
        });
        throw httpError(503, 'PAYOUT_STATE_UNKNOWN');
      }
      // seen.state === 'absent' — the gateway has no such payout, so this
      // withdrawal genuinely never went out and dispatching is safe.
    } else if (!PAYOUT_RETRYABLE.has(withdrawal.status)) {
      // `requested` means the reserve never committed — nothing is held, so
      // there is nothing to pay out. Refuse rather than silently paying.
      throw httpError(409, `WITHDRAWAL_NOT_RESERVED:${withdrawal.status}`);
    }

    // Claim the disbursement before calling the provider so a concurrent
    // worker sees `disbursing` and backs off. `payoutAttemptedAt` is the durable
    // "we may have called the gateway" marker: it is written BEFORE the call, so
    // a crash between the call and the response leaves evidence to reconcile.
    if (withdrawal.status !== WITHDRAWAL_STATUS.DISBURSING) {
      const claimed = await ref.update({
        status: WITHDRAWAL_STATUS.DISBURSING,
        disbursingAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      void claimed;
    }
    await ref.update({
      payoutAttemptedAt: FieldValue.serverTimestamp(),
      needsManualReview: FieldValue.delete(),
      needsManualReviewReason: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const provider = getProvider(withdrawal.provider || 'clickpesa');
    const payout = await provider.initiatePayout({
      amount: withdrawal.amount,
      orderReference,
      phoneNumber: await withdrawalPayoutPhone(withdrawal, { db }),
    });

    await ref.update({
      status: WITHDRAWAL_STATUS.PROCESSING,
      providerPayoutId: payout.id || payout.providerPayoutId || null,
      processedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await db
      .collection(commerceStore.COLLECTIONS.payoutTransactions)
      .doc(String(withdrawalId))
      .set(
        {
          withdrawalId: String(withdrawalId),
          sellerId: withdrawal.sellerId,
          amount: withdrawal.amount,
          providerResponse: payout,
          status: 'processing',
          executedBy,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    return commerceStore.serializeWithdrawal(await ref.get());
  } catch (err) {
    // A definitive provider rejection (bad number, closed account, limit)
    // must not leave the seller's money reserved forever.
    if (err && err.definitive === true) {
      await _failWithdrawal({ db, withdrawalId, reason: err.message || 'PAYOUT_REJECTED' });
    }
    throw err;
  } finally {
    if (lock.acquired) await releaseLock(`withdraw:${withdrawalId}`, lock.token);
  }
}

/**
 * Terminally fails a withdrawal and returns the reserved funds.
 *
 * Status flip, wallet credit and the immutable refund ledger entry are ONE
 * Firestore transaction. This was previously two transactions: the first set
 * `status: failed` + `refundLedgerWritten: true`, and only then did the second
 * credit the wallet. A crash in that gap left a withdrawal that looked
 * permanently settled while the seller's TSh was still deducted, and
 * `refundLedgerWritten` — the only guard against a double refund — was already
 * set, so the retry path skipped it. There is no longer a gap: the money and
 * the flag that describes it commit together or not at all.
 *
 * Returns `{ refunded: false }` when nothing was done (already terminal,
 * already refunded, or missing), so callers can tell a no-op from a refund.
 */
async function _failWithdrawal({ db, withdrawalId, reason }) {
  const store = db || getFirebaseFirestore();
  const ref = store
    .collection(commerceStore.COLLECTIONS.withdrawals)
    .doc(String(withdrawalId));
  const refundLedgerId = commerceStore.buildLedgerId(
    `ledger_withdrawal_refund_${withdrawalId}`,
  );

  let outcome = { refunded: false, reason: 'no_op' };

  try {
    outcome = await store.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { refunded: false, reason: 'not_found' };
      const d = snap.data() || {};

      // Never refund a withdrawal that already completed or already refunded.
      if (
        d.status === WITHDRAWAL_STATUS.COMPLETED
        || d.status === WITHDRAWAL_STATUS.FAILED
        || d.refundLedgerWritten === true
      ) {
        return { refunded: false, reason: 'already_terminal' };
      }

      const seller = String(d.sellerId);
      const amt = Math.abs(Number(d.amount) || 0);
      const wRef = store.collection(commerceStore.COLLECTIONS.wallets).doc(seller);
      const refundRef = store.collection(commerceStore.COLLECTIONS.ledger).doc(refundLedgerId);

      // All reads before any write — Firestore requires this ordering.
      const wSnap = amt > 0 ? await t.get(wRef) : null;
      const refundSnap = amt > 0 ? await t.get(refundRef) : null;

      if (refundSnap && refundSnap.exists) {
        // Money already returned by an earlier attempt; just close the record.
        t.set(ref, {
          status: WITHDRAWAL_STATUS.FAILED,
          failureReason: String(reason).slice(0, 300),
          refundLedgerWritten: true,
          failedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        return { refunded: false, reason: 'already_refunded' };
      }

      if (wSnap && wSnap.exists && amt > 0) {
        const prior = commerceStore.tzs(wSnap.data().availableBalance || 0);
        const next = prior + amt;
        t.update(wRef, {
          availableBalance: next,
          updatedAt: FieldValue.serverTimestamp(),
        });
        t.set(refundRef, {
          walletId: seller,
          type: commerceStore.LEDGER_TYPES.WITHDRAWAL_REFUNDED,
          amount: amt,
          balanceAfter: next,
          referenceType: 'withdrawal',
          referenceId: String(withdrawalId),
          idempotencyKey: refundLedgerId,
          description: 'Withdrawal refunded — payout failed',
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      t.set(ref, {
        status: WITHDRAWAL_STATUS.FAILED,
        failureReason: String(reason).slice(0, 300),
        refundLedgerWritten: true,
        failedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });

      return { refunded: amt > 0, reason: 'refunded', sellerId: seller, amount: amt };
    });
  } catch (e) {
    // Never let refund bookkeeping mask the original failure.
    console.error(`[wallet] failed to refund withdrawal ${withdrawalId}: ${e.message}`);
    return { refunded: false, reason: 'error' };
  }

  if (outcome.refunded || outcome.reason === 'already_refunded') {
    await store
      .collection(commerceStore.COLLECTIONS.payoutTransactions)
      .doc(String(withdrawalId))
      .set(
        {
          withdrawalId: String(withdrawalId),
          sellerId: outcome.sellerId || null,
          amount: outcome.amount || 0,
          status: 'failed',
          failureReason: String(reason).slice(0, 300),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }

  return outcome;
}

/**
 * Marks a withdrawal paid after the provider confirms it.
 *
 * The status flip and the `totalWithdrawn` increment happen in ONE transaction.
 * Previously they were two independent writes guarded by a stale read, so two
 * concurrent confirms both passed the `status !== 'completed'` check and both
 * incremented the counter.
 */
async function confirmPayout({ withdrawalId, providerPayoutId }) {
  const lock = await requireLock(`withdraw:${withdrawalId}`, 60);
  const db = getFirebaseFirestore();

  try {
    const ref = db
      .collection(commerceStore.COLLECTIONS.withdrawals)
      .doc(String(withdrawalId));
    const wRef = db
      .collection(commerceStore.COLLECTIONS.wallets)
      .doc(String(await _sellerIdFor(db, withdrawalId)));

    let completed;
    await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
      const d = snap.data() || {};
      if (d.status === WITHDRAWAL_STATUS.COMPLETED) {
        completed = true;
        return;
      }
      const wSnap = await t.get(wRef);
      t.set(ref, {
        status: WITHDRAWAL_STATUS.COMPLETED,
        providerPayoutId: providerPayoutId || d.providerPayoutId || null,
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });

      // Bookkeeping only — the balance was already debited at reserve time.
      const walletData = wSnap.exists ? wSnap.data() || {} : {};
      t.set(wRef, {
        sellerId: String(d.sellerId),
        totalWithdrawn: commerceStore.tzs(walletData.totalWithdrawn || 0) + Math.abs(d.amount || 0),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      completed = false;
    });

    const snap = await ref.get();
    const current = commerceStore.serializeWithdrawal(snap);

    if (!completed) {
      await db
        .collection(commerceStore.COLLECTIONS.payoutTransactions)
        .doc(String(withdrawalId))
        .set(
          {
            withdrawalId: String(withdrawalId),
            sellerId: current.sellerId,
            amount: current.amount,
            providerResponse: { providerPayoutId },
            status: 'completed',
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
    }

    return current;
  } finally {
    if (lock.acquired) await releaseLock(`withdraw:${withdrawalId}`, lock.token);
  }
}

async function _sellerIdFor(db, withdrawalId) {
  const snap = await db
    .collection(commerceStore.COLLECTIONS.withdrawals)
    .doc(String(withdrawalId))
    .get();
  if (!snap.exists) throw httpError(404, 'WITHDRAWAL_NOT_FOUND');
  return (snap.data() || {}).sellerId;
}

/**
 * Ports a legacy Firestore `users/{uid}` sellerBalance into the wallet with an
 * idempotent `legacy_balance_{uid}` ledger entry so the cutover never credits
 * twice even if the script re-runs.
 */
async function creditLegacyBalance({ sellerId, amount, priorWithdrawn = 0 }) {
  const amt = Math.round(Number(amount));
  const withdrawn = Math.round(Number(priorWithdrawn));
  if (!Number.isFinite(amt) || amt <= 0) throw httpError(400, 'INVALID_AMOUNT');
  const lock = await requireLock(`legacy:${sellerId}`, 60);

  try {
    const prior = await commerceStore.getWallet(sellerId);
    // A wallet whose ledger already has the legacy entry is considered migrated.
    const { ledger } = await commerceStore.listLedger(sellerId, { page: 1, limit: 100 });
    const hasLegacyEntry = ledger.some(
      (e) => e.referenceType === 'legacy_balance' && e.referenceId === String(sellerId),
    );
    if (hasLegacyEntry) return { alreadyMigrated: true, sellerId };

    await commerceStore.postLedger({
      sellerUid: sellerId,
      amount: amt,
      type: commerceStore.LEDGER_TYPES.LEGACY_BALANCE,
      referenceType: 'legacy_balance',
      referenceId: String(sellerId),
      idempotencyKey: `legacy_balance_${sellerId}`,
      description: 'Firestore sellerBalance migrated at wallet cutover',
    });

    if (withdrawn > 0) {
      await getFirebaseFirestore()
        .collection(commerceStore.COLLECTIONS.wallets)
        .doc(String(sellerId))
        .set({
          totalWithdrawn: require('firebase-admin/firestore').FieldValue.increment(withdrawn),
          updatedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp(),
        }, { merge: true });
    }

    void prior;
    return { alreadyMigrated: false, sellerId, amount: amt };
  } finally {
    if (lock.acquired) await releaseLock(`legacy:${sellerId}`, lock.token);
  }
}

/**
 * Resolves the phone number a withdrawal pays out to: the phone captured at
 * request time wins; legacy rows fall back to the seller's user profile phone.
 */
// Thin wrapper kept because callers (and tests) already depend on this name.
// The lookup itself lives in services/payout-phone: the Firestore `users`
// collection is keyed by Firebase UID, so the previous version — which used
// withdrawal.sellerId, a database UUID — could never find the document and
// every seller without a database phone was refused a payout.
async function withdrawalPayoutPhone(withdrawal, { db, userPhone } = {}) {
  if (withdrawal.phoneNumber) return withdrawal.phoneNumber;
  if (userPhone) return userPhone;
  if (withdrawal.seller && withdrawal.seller.user && withdrawal.seller.user.phone) {
    return withdrawal.seller.user.phone;
  }
  return resolvePayoutPhone({
    db,
    firebaseUid: withdrawal.seller && withdrawal.seller.user && withdrawal.seller.user.firebaseUid,
    userId: withdrawal.sellerId,
  });
}

async function listWithdrawals(sellerId) {
  return commerceStore.listWithdrawals(sellerId);
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

module.exports = {
  getWallet,
  getWalletDetail,
  ensureWallet,
  requestWithdrawal,
  processWithdrawal,
  confirmPayout,
  creditLegacyBalance,
  withdrawalPayoutPhone,
  listWithdrawals,
  // Exported for the finance sweep and for tests that assert the state machine.
  WITHDRAWAL_STATUS,
  PAYOUT_RETRYABLE,
  PAYOUT_REVERIFYABLE,
  PAYOUT_AWAITING_CONFIRMATION,
  PAYOUT_TERMINAL,
  reserveWithdrawalFunds,
  releaseWithdrawalReservation,
};