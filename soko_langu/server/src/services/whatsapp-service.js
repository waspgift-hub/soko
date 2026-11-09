// WhatsApp delivery via Zernio API (sandbox, no KYC required).
//
// Provider surface mirrors sms-service.js: { name, available(), send({ to, message }) }.
// Sandbox limits: one test phone, 50 messages/day, one template.
// The recipient must reply to the activation template before free-form sends work
// (opens the 24-hour WhatsApp customer-service window).
const axios = require('axios');
const { createBreaker } = require('../utils/circuit-breaker');
const { maskPhone } = require('../utils/pii');

const ZERNIO_BASE_URL = 'https://zernio.com/api/v1';
const zernioBreaker = createBreaker('whatsapp-zernio', { failureThreshold: 3 });

let sandboxCache = null;
let sandboxCacheTs = 0;

async function fetchSandbox(apiKey) {
  const now = Date.now();
  if (sandboxCache && now - sandboxCacheTs < 300000) return sandboxCache; // 5 min TTL
  const resp = await axios.get(`${ZERNIO_BASE_URL}/phone-numbers`, {
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    timeout: 15000,
  });
  sandboxCache = resp.data;
  sandboxCacheTs = now;
  return sandboxCache;
}

async function activateSandboxSession(apiKey, phone) {
  const resp = await axios.post(`${ZERNIO_BASE_URL}/whatsapp/sandbox/sessions`, { phone }, {
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    timeout: 15000,
  });
  return resp.data;
}

async function listSandboxSessions(apiKey) {
  const resp = await axios.get(`${ZERNIO_BASE_URL}/whatsapp/sandbox/sessions`, {
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    timeout: 15000,
  });
  return resp.data;
}

async function sendInboxConversation(apiKey, { accountId, participantId, templateName, templateLanguage, templateParams = [], message }) {
  // Free-form text inside an active 24h customer-service window:
  // POST /v1/inbox/conversations/{conversationId}/messages
  // We need an existing conversationId; if none provided, fall back to template
  // conversation creation via POST /v1/inbox/conversations.
  if (message) {
    // Look up or create a conversation first, then send free-form message.
    // Try to find existing conversation for this participant.
    const convResp = await axios.get(`${ZERNIO_BASE_URL}/inbox/conversations`, {
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
      params: { participantId, accountId },
    });
    let conversationId = null;
    const convs = convResp.data && convResp.data.data ? convResp.data.data : [];
    for (const c of convs) {
      if (c.participantId === participantId || c.participantId === String(participantId)) {
        conversationId = c.id || c.conversationId;
        break;
      }
    }
    if (!conversationId) {
      // Create a template conversation first (opens the window), then send free-form.
      const created = await axios.post(`${ZERNIO_BASE_URL}/inbox/conversations`, {
        accountId,
        participantId,
        templateName: templateName || '',
        templateLanguage: templateLanguage || 'en',
        templateParams: [],
      }, {
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        timeout: 15000,
      });
      conversationId = created.data?.data?.conversationId || created.data?.conversationId;
    }

    const msgResp = await axios.post(`${ZERNIO_BASE_URL}/inbox/conversations/${conversationId}/messages`, {
      accountId,
      message,
    }, {
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    return msgResp.data;
  }

  const resp = await axios.post(`${ZERNIO_BASE_URL}/inbox/conversations`, {
    accountId,
    participantId,
    templateName,
    templateLanguage,
    templateParams,
  }, {
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    timeout: 15000,
  });
  return resp.data;
}

const ZernioWhatsAppProvider = {
  name: 'zernio-whatsapp',
  available() {
    return Boolean(process.env.ZERNIO_API_KEY);
  },
  async send({ to, message }) {
    const apiKey = process.env.ZERNIO_API_KEY;
    if (!apiKey) return false;

    // WhatsApp via sandbox requires the recipient to be activated first.
    // Try to activate; if already active, send a template conversation.
    try {
      const sandbox = await fetchSandbox(apiKey);
      if (!sandbox || !sandbox.sandbox) {
        console.error('[WA] zernio sandbox not configured on this account');
        return false;
      }

    // Check if session is active first (recipient must have replied).
    const sessions = await zernioBreaker.call(
      () => listSandboxSessions(apiKey),
      () => null
    );
    const session = (sessions && sessions.sessions && sessions.sessions[0]) || null;
    if (!session || session.status !== 'active') {
      // Not active yet — try to activate (sends template to recipient).
      try {
        await zernioBreaker.call(
          () => activateSandboxSession(apiKey, to),
          () => null
        );
      } catch (e) {
        // ignore — session may already exist
      }
      console.error(`[WA] zernio sandbox session not active for ${maskPhone(to)} — recipient must reply to activation template`);
      return false;
    }

    const tmpl = sandbox.sandbox.template || {};
    await zernioBreaker.call(
      () => sendInboxConversation(apiKey, {
        accountId: sandbox.sandbox.accountId,
        participantId: to.replace(/\D/g, ''),
        templateName: tmpl.name || '',
        templateLanguage: tmpl.language || 'en',
        templateParams: [],
      }),
      () => null
    );
    console.log(`[WA] zernio-whatsapp ok to=${maskPhone(to)}`);
    return true;
    } catch (e) {
      const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
      console.error(`[WA] zernio-whatsapp error: ${errBody}`);
      return false;
    }
  },
};

async function sendWhatsApp(phone, message) {
  if (!phone || !message) return false;
  return ZernioWhatsAppProvider.send({ to: phone, message });
}

module.exports = {
  sendWhatsApp,
  ZernioWhatsAppProvider,
  activateSandboxSession,
  listSandboxSessions,
  sendInboxConversation,
  fetchSandbox,
};
