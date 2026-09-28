const { Router } = require('express');
const { getFirebaseAuth } = require('../../config/firebase');
const gateway = require('./ai-gateway');
const { chatWithTools } = require('./tool-loop');

const router = Router();

// Bearer Firebase ID token. The LLM API keys never leave the server, so this
// is the only thing the app proves: that the caller is a real Soko Vibe user.
async function requireUser(req, res) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or invalid token' });
    return null;
  }
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      res.status(503).json({ error: 'Auth not configured' });
      return null;
    }
    const decoded = await auth.verifyIdToken(authHeader.slice(7));
    return decoded;
  } catch {
    res.status(401).json({ error: 'Invalid token' });
    return null;
  }
}

router.post('/chat', async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;

  const { model, messages, temperature, max_tokens } = req.body || {};
  if (!model || !Array.isArray(messages)) {
    return res.status(400).json({ error: 'model and messages[] required' });
  }

  // Tool use is on by default so the already-shipped app benefits without a
  // rebuild, but it can be switched off per request and globally, because it
  // costs an extra provider round trip when the model decides to use a tool.
  const useTools = req.body?.tools !== false && process.env.AI_TOOLS_ENABLED !== 'false';
  const body = { model, messages, temperature, max_tokens };

  try {
    const result = useTools
      ? await chatWithTools(body, user.uid)
      : await gateway.chat(body);
    // Lets support answer "which provider served this?" without reading logs.
    res.set('X-AI-Provider', result.provider);
    if (result.failedOver) res.set('X-AI-Failed-Over', '1');
    if (result.toolsUsed?.length) res.set('X-AI-Tools', result.toolsUsed.join(','));
    res.set('Content-Type', 'application/json');
    res.send(result.text);
  } catch (e) {
    // Provider status is preserved so the client can tell 429 (busy) from 503
    // (not configured) from 500 (broken).
    if (e.code === 'AI_NO_PROVIDER') {
      return res
        .status(503)
        .json({ error: 'No AI provider configured on server (GROQ_API_KEY or GEMINI_API_KEY)' });
    }
    console.error('[ai] chat failed:', e.message);
    res.status(e.status || 500).json({ error: 'AI service error' });
  }
});

router.post('/transcribe', async (req, res) => {
  const user = await requireUser(req, res);
  if (!user) return;

  const { audio, model, language } = req.body || {};
  if (!audio) {
    return res.status(400).json({ error: 'audio (base64) required' });
  }

  try {
    const text = await gateway.transcribe({
      audioBase64: audio,
      model,
      language,
    });
    res.set('Content-Type', 'application/json');
    res.send(text);
  } catch (e) {
    if (e.code === 'AI_NOT_CONFIGURED' || e.code === 'AI_NO_PROVIDER') {
      return res
        .status(503)
        .json({ error: 'Groq API key not configured on server' });
    }
    console.error('[ai] transcribe failed:', e.message);
    res.status(e.status || 500).json({ error: 'AI transcription error' });
  }
});

module.exports = router;
module.exports.gatewayStatus = gateway.status;
