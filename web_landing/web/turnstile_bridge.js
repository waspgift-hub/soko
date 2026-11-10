(function () {
  window.svTurnstile = window.svTurnstile || {};
  var widgets = {};
  var tokens = {};
  var pending = {};
  var scriptReady = null;

  function ensureScript() {
    if (window.turnstile) return Promise.resolve(window.turnstile);
    if (scriptReady) return scriptReady;
    scriptReady = new Promise(function (resolve) {
      var tries = 0;
      function tick() {
        if (window.turnstile) return resolve(window.turnstile);
        tries += 1;
        if (tries > 200) return resolve(null);
        setTimeout(tick, 50);
      }
      tick();
    });
    return scriptReady;
  }

  window.svTurnstile.render = function (containerId, siteKey, action) {
    return ensureScript().then(function (ts) {
      if (!ts) return;
      var el = document.getElementById(containerId);
      if (!el) return;
      if (widgets[containerId] !== undefined) return;
      try {
        widgets[containerId] = ts.render(el, {
          sitekey: siteKey,
          action: action || 'submit',
          theme: 'light',
          callback: function (token) {
            tokens[containerId] = token || '';
            if (pending[containerId]) {
              pending[containerId](tokens[containerId]);
              delete pending[containerId];
            }
          },
          'expired-callback': function () { tokens[containerId] = ''; },
          'error-callback': function () { tokens[containerId] = ''; }
        });
      } catch (e) {}
    });
  };

  window.svTurnstile.getToken = function (containerId) {
    return tokens[containerId] || '';
  };

  window.svTurnstile.reset = function (containerId) {
    var id = widgets[containerId];
    if (window.turnstile && (id || id === 0)) {
      try { window.turnstile.reset(id); } catch (e) {}
    }
    tokens[containerId] = '';
  };
})();
