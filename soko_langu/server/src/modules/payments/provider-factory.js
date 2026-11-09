const AzamPayProvider = require('./azampay-provider');

let azampay;

/**
 * Returns the AzamPay provider instance (singleton).
 * ClickPesa has been removed entirely — use AZAMPAY_* env vars instead.
 */
function getProvider(name = 'azampay') {
  switch (name) {
    case 'azampay':
    case 'mno_checkout':
      if (!azampay) azampay = new AzamPayProvider();
      return azampay;
    default:
      throw new Error(`UNSUPPORTED_PROVIDER: ${name}`);
  }
}

module.exports = { getProvider };
