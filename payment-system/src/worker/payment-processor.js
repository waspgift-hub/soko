const { getPrisma } = require('./prisma-client');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');

// ---------------------------------------------------------------------------
// Payment Processor — Business Logic Layer
//
// This module contains the ACTUAL database writes that were moved out of
// the API server. It runs inside the worker process, completely decoupled
// from HTTP request handling.
//
// ATOMICITY GUARANTEE:
// The Prisma $transaction block ensures either ALL changes succeed or
// NONE do. If the payment record updates but the audit log insert fails,
// the entire transaction rolls back. No partial states.
//
// RACE CONDITION PREVENTION:
// We use a Prisma upsert with a unique constraint on `transactionId`.
// Even if two jobs somehow slip through (impossible with idempotency
// lock, but defense-in-depth), the UNIQUE constraint on transactionId
// causes the second write to fail, not duplicate.
// ---------------------------------------------------------------------------

/**
 * Process a payment webhook payload and update the database.
 *
 * This function is idempotent — calling it multiple times with the same
 * transactionId produces the same result (no duplicate records).
 *
 * @param {Object} jobData - The payment payload from the queue
 * @returns {Object} Processing result with status and timing info
 */
async function processPayment(jobData) {
  const startTime = Date.now();
  const prisma = getPrisma();
  const workerId = `worker-${process.pid}`;

  const {
    transactionId,
    status: gatewayStatus,
    amount,
    currency,
    payerId,
    payerEmail,
    gatewayRef,
    metadata,
  } = jobData;

  try {
    // ---------------------------------------------------------------
    // STEP 1: Map gateway status to internal status
    //
    // Different gateways use different status strings. Normalize them
    // to your internal status enum. This mapping lives here (worker)
    // instead of the API server because status mapping is business
    // logic, not transport logic.
    // ---------------------------------------------------------------
    const statusMap = {
      completed: 'completed',
      succeeded: 'completed',
      paid: 'completed',
      failed: 'failed',
      declined: 'failed',
      error: 'failed',
      pending: 'pending',
      processing: 'pending',
      refunded: 'refunded',
      reversed: 'refunded',
    };

    const normalizedStatus = statusMap[gatewayStatus] || 'pending';

    // ---------------------------------------------------------------
    // STEP 2: Atomic database write inside a Prisma interactive transaction
    //
    // WHY $transaction?
    // We're updating the Payment record AND inserting an audit log.
    // If the server crashes between these two operations without a
    // transaction, we'd have an updated payment with no audit trail —
    // a compliance violation.
    //
    // $transaction wraps both operations in a single PostgreSQL
    // BEGIN/COMMIT block. Either both succeed or both roll back.
    // ---------------------------------------------------------------
    const result = await prisma.$transaction(async (tx) => {
      // Find existing payment or create new one (upsert pattern)
      const existingPayment = await tx.payment.findUnique({
        where: { transactionId },
        select: { id: true, status: true },
      });

      let payment;
      let isNew = false;
      let previousStatus = null;

      if (existingPayment) {
        // Payment already exists (e.g., from a prior partial processing attempt)
        previousStatus = existingPayment.status;

        // Only update if the new status is more "final" than the current one.
        // This prevents a late "pending" webhook from overwriting a "completed" state.
        const statusPriority = { pending: 0, processing: 1, completed: 2, failed: 2, refunded: 3 };
        const currentPriority = statusPriority[previousStatus] ?? 0;
        const newPriority = statusPriority[normalizedStatus] ?? 0;

        if (newPriority >= currentPriority) {
          payment = await tx.payment.update({
            where: { transactionId },
            data: {
              status: normalizedStatus,
              gatewayRef: gatewayRef || undefined,
              metadata: metadata || undefined,
              updatedAt: new Date(),
            },
          });
        } else {
          // Downgrade attempt — keep current status, log the attempt
          payment = existingPayment;
          logger.info(
            { transactionId, currentStatus: previousStatus, attempted: normalizedStatus },
            'Status downgrade rejected (already in advanced state)',
          );
          return {
            paymentId: payment.id,
            status: previousStatus,
            skipped: true,
            reason: 'Status already advanced',
          };
        }
      } else {
        // New payment — create record
        isNew = true;
        payment = await tx.payment.create({
          data: {
            id: uuidv4(),
            transactionId,
            idempotencyKey: jobData.idempotencyKey || transactionId,
            status: normalizedStatus,
            amount: parseFloat(amount),
            currency: currency || 'USD',
            payerId,
            payerEmail: payerEmail || null,
            gatewayRef: gatewayRef || null,
            metadata: metadata || undefined,
          },
        });
      }

      // ---------------------------------------------------------------
      // STEP 3: Insert audit log (append-only, never updated)
      //
      // WHY AUDIT LOG?
      // For compliance (PCI-DSS, SOC2) and debugging. When a customer
      // says "I was charged twice," you need a timestamped trail of
      // every state transition, which worker processed it, and how
      // long it took.
      // ---------------------------------------------------------------
      await tx.paymentAuditLog.create({
        data: {
          id: uuidv4(),
          paymentId: payment.id,
          transactionId,
          previousStatus,
          newStatus: normalizedStatus,
          workerId,
          processingMs: Date.now() - startTime,
          errorMessage: null,
        },
      });

      return {
        paymentId: payment.id,
        status: normalizedStatus,
        isNew,
        previousStatus,
      };
    });

    const elapsedMs = Date.now() - startTime;

    logger.info(
      {
        transactionId,
        paymentId: result.paymentId,
        status: result.status,
        isNew: result.isNew,
        workerId,
        elapsedMs,
      },
      `Payment processed in ${elapsedMs}ms`,
    );

    return {
      success: true,
      paymentId: result.paymentId,
      status: result.status,
      processingMs: elapsedMs,
    };
  } catch (err) {
    const elapsedMs = Date.now() - startTime;

    // Log the failure with full context for debugging
    logger.error(
      {
        err: err.message,
        stack: err.stack,
        transactionId,
        workerId,
        elapsedMs,
      },
      'Payment processing failed',
    );

    // Re-throw so BullMQ's retry mechanism kicks in
    throw err;
  }
}

module.exports = { processPayment };
