// ─── Mongike Payment Gateway ──────────────────────────────────
// Base URL: https://mongike.com/api/v1
// Auth: x-api-key header
// Collection fee: 180 TZS flat (absorbed by platform)
// Payout fee: 2,000 TZS flat (deducted from seller)

const MONGIKE_BASE_URL = 'https://mongike.com/api/v1';
const MONGIKE_API_KEY = process.env.MONGIKE_API_KEY || '';

const COLLECTION_FEE = 180;
const PAYOUT_FEE = 2000;

/**
 * Normalize Mongike API response to a consistent shape.
 * Different Mongike endpoints may return different response envelopes.
 */
function normalizeResponse(raw) {
  const data = raw.data || raw;
  return {
    id: data.id || data.transactionId || data.reference || '',
    status: (data.status || '').toLowerCase(),
    amount: data.amount || 0,
    orderReference: data.orderReference || data.order_id || data.externalId || '',
    message: data.message || data.description || '',
    raw: raw,
  };
}

/**
 * Initiate mobile money collection (USSD push) via Mongike.
 * Mongike pushes a USSD prompt to the buyer's phone — they enter their PIN to complete.
 *
 * @param {Object} params
 * @param {number} params.amount - Amount in TZS (180 TZS fee absorbed by platform)
 * @param {string} params.orderId - Unique order identifier
 * @param {string} params.buyerPhone - Buyer's phone number (no leading +, digits only)
 * @param {string} [params.buyerName] - Buyer's display name
 * @param {string} [params.buyerEmail] - Buyer's email
 * @param {'MERCHANT'|'CUSTOMER'} [params.feePayer='MERCHANT'] - Who pays the gateway fee
 * @param {Object} [params.metadata] - Arbitrary metadata to attach
 * @returns {Promise<{id: string, status: string, amount: number, orderReference: string, message: string, raw: Object}>}
 */
async function mongikeCollect({ amount, orderId, buyerPhone, buyerName, buyerEmail, feePayer, metadata }) {
  const payload = {
    order_id: orderId,
    amount: Math.round(amount),
    buyer_phone: buyerPhone.replace(/[^0-9]/g, ''),
    fee_payer: feePayer || 'MERCHANT',
  };
  if (buyerName) payload.buyer_name = buyerName;
  if (buyerEmail) payload.buyer_email = buyerEmail;
  if (metadata) payload.metadata = metadata;

  let resp;
  try {
    resp = await fetch(`${MONGIKE_BASE_URL}/payments/mobile-money/tanzania`, {
      method: 'POST',
      headers: {
        'x-api-key': MONGIKE_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
  } catch (networkErr) {
    throw new Error(`Mongike network error: ${networkErr.message}`);
  }

  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {
    throw new Error(`Mongike non-JSON response (${resp.status}): ${text.slice(0, 200)}`);
  }
  if (!resp.ok) {
    throw new Error(data.message || data.error || `Mongike collection failed (${resp.status})`);
  }
  return normalizeResponse(data);
}

/**
 * Send payout to a mobile money recipient via Mongike.
 * Flat 2,000 TZS fee is deducted from the payout amount or the sender's balance.
 *
 * @param {Object} params
 * @param {number} params.amount - Amount to send in TZS (fee deducted separately)
 * @param {string} params.recipientPhone - Recipient's phone number
 * @param {string} [params.recipientName] - Recipient's name
 * @param {string} [params.narration] - Transaction narration
 * @param {string} [params.externalReference] - Unique reference for this payout (payoutId)
 * @returns {Promise<{id: string, status: string, amount: number, orderReference: string, message: string, raw: Object}>}
 */
async function mongikePayout({ amount, recipientPhone, recipientName, narration, externalReference }) {
  const payload = {
    amount: Math.round(amount),
    recipient_phone: recipientPhone.replace(/[^0-9]/g, ''),
  };
  if (recipientName) payload.recipient_name = recipientName;
  if (narration) payload.narration = narration;
  if (externalReference) payload.orderReference = externalReference;

  let resp;
  try {
    resp = await fetch(`${MONGIKE_BASE_URL}/payouts/withdraw`, {
      method: 'POST',
      headers: {
        'x-api-key': MONGIKE_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
  } catch (networkErr) {
    throw new Error(`Mongike payout network error: ${networkErr.message}`);
  }

  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {
    throw new Error(`Mongike payout non-JSON response (${resp.status}): ${text.slice(0, 200)}`);
  }
  if (!resp.ok) {
    throw new Error(data.message || data.error || `Mongike payout failed (${resp.status})`);
  }
  return normalizeResponse(data);
}

/**
 * Get wallet balance from Mongike.
 * @returns {Promise<number>} Current balance in TZS
 */
async function mongikeBalance() {
  let resp;
  try {
    resp = await fetch(`${MONGIKE_BASE_URL}/wallet/balance`, {
      method: 'GET',
      headers: { 'x-api-key': MONGIKE_API_KEY },
    });
  } catch (networkErr) {
    throw new Error(`Mongike balance network error: ${networkErr.message}`);
  }

  const text = await resp.text();
  let data = {};
  try { data = JSON.parse(text); } catch (_) {
    throw new Error(`Mongike balance non-JSON response (${resp.status}): ${text.slice(0, 200)}`);
  }
  if (!resp.ok) throw new Error(data.message || data.error || `Mongike balance failed (${resp.status})`);
  return data.data?.balance || data.balance || 0;
}

module.exports = { mongikeCollect, mongikePayout, mongikeBalance, COLLECTION_FEE, PAYOUT_FEE };
