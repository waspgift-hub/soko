/**
 * Payment Provider Interface (Abstract)
 * 
 * All payment providers (ClickPesa, future bank providers) must implement
 * this contract. The rest of the system depends only on this interface,
 * never on a concrete provider.
 */

class PaymentProvider {
  /**
   * Initiate a collection (payment). Returns a provider-specific instruction
   * the buyer acts on (e.g. USSD push) and a provider reference.
   */
  async initiateCollection({ amount, orderReference, phoneNumber, callbackUrl }) {
    throw new Error('Not implemented');
  }

  /**
   * Query status of a previously initiated collection by provider reference.
   * Returns { status, providerPaymentId, raw }.
   */
  async queryCollectionStatus(orderReference) {
    throw new Error('Not implemented');
  }

  /**
   * Initiate a payout (disbursement) to a recipient.
   */
  async initiatePayout({ amount, orderReference, phoneNumber }) {
    throw new Error('Not implemented');
  }

  /**
   * Verify an incoming webhook payload is authentic (HMAC / secret).
   * Returns boolean.
   */
  verifyWebhook(payload, signature) {
    throw new Error('Not implemented');
  }

  /**
   * Normalize a provider webhook/success payload into a standard shape:
   * { orderReference, providerPaymentId, amount, status, raw }
   */
  normalizeWebhook(payload) {
    throw new Error('Not implemented');
  }

  /**
   * Provider identifier: 'clickpesa' | 'card' | 'bank' ...
   */
  get name() {
    throw new Error('Not implemented');
  }
}

module.exports = PaymentProvider;
