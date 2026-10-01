/**
 * Error type for payment failures that are the CUSTOMER's problem rather than
 * ours: an empty M-Pesa wallet, a wrong PIN, a cancelled USSD prompt.
 *
 * Why it exists: the gateway reports these as a normal payment with
 * `status: "FAILED"` and a human `message` ("You do not have enough balance to
 * do this transaction. Please top up your account"), and the whole order
 * treatment that follows from that is different from an infrastructure failure.
 * A customer with no balance is retried by the customer, not by the platform,
 * and must not trip the circuit breaker that protects the gateway.
 *
 * The message is carried through from the gateway rather than replaced, because
 * it is the only place the real reason appears and it is already written for a
 * human. It is the gateway's own text about the customer's own money, not
 * something we are asserting on its behalf.
 */
class PaymentError extends Error {
  constructor({ code, message, provider, status, providerReference, retryable = false }) {
    super(message || code);
    this.name = 'PaymentError';
    this.code = code || 'PAYMENT_FAILED';
    this.provider = provider;
    this.status = status || 402;
    this.providerReference = providerReference || null;
    this.retryable = retryable;
    // A customer-side decline is NOT a provider outage. The breaker keys on this
    // to stay closed: otherwise a burst of underfunded buyers would open the
    // circuit and block every legitimate payment behind them.
    this.isProviderFault = false;
  }
}

module.exports = { PaymentError };
