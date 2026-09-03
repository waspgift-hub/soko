const ClickPesaProvider = require('./clickpesa-provider');

let clickpesa;

/**
 * Returns the ClickPesa provider instance (singleton).
 */
function getProvider(name = 'clickpesa') {
  switch (name) {
    case 'clickpesa':
    case 'ussd_push':
    case 'billpay':
      if (!clickpesa) clickpesa = new ClickPesaProvider();
      return clickpesa;
    default:
      throw new Error(`UNSUPPORTED_PROVIDER: ${name}`);
  }
}

module.exports = { getProvider };
