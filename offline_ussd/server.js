#!/usr/bin/env node
'use strict';

const http = require('node:http');
const os = require('node:os');
const crypto = require('node:crypto');

const PORT = Number(process.env.USSD_PORT || 8787);
const HOST = process.env.USSD_HOST || '0.0.0.0';
const TOKEN = process.env.USSD_TOKEN || crypto.randomBytes(4).toString('hex').toUpperCase();
const sessions = new Map();

const menus = {
  '*123#': { title: 'SOKO LANGU', text: 'Chagua huduma:\n1. Nunua\n2. Uza bidhaa\n3. Akaunti\n4. Msaada', options: ['1', '2', '3', '4'] },
  '1': { title: 'NUNUA', text: '1. Bidhaa mpya\n2. Tafuta bidhaa\n0. Rudi', options: ['1', '2', '0'] },
  '2': { title: 'UZA BIDHAA', text: '1. Ongeza bidhaa\n2. Oda zangu\n0. Rudi', options: ['1', '2', '0'] },
  '3': { title: 'AKAUNTI', text: '1. Salio\n2. Wasifu\n0. Rudi', options: ['1', '2', '0'] },
  '4': { title: 'MSAADA', text: 'Karibu Soko Langu support.\n1. Namna ya kutumia\n2. Wasiliana nasi\n0. Rudi', options: ['1', '2', '0'] },
  '1:1': { title: 'BIDHAA MPYA', text: 'Bidhaa mpya zinapatikana sokoni.\n0. Rudi', options: ['0'] },
  '1:2': { title: 'TAFUTA', text: 'Ingiza neno la kutafuta bidhaa.\n0. Rudi', options: ['0'] },
  '2:1': { title: 'ONGEZA BIDHAA', text: 'Ingiza jina la bidhaa kuendelea.\n0. Rudi', options: ['0'] },
  '2:2': { title: 'ODA ZANGU', text: 'Huna oda mpya kwa sasa.\n0. Rudi', options: ['0'] },
  '3:1': { title: 'SALIO', text: 'Salio la cash: TSh 0\n0. Rudi', options: ['0'] },
  '3:2': { title: 'WASIFU', text: 'Akaunti ya Soko Langu\n0. Rudi', options: ['0'] },
  '4:1': { title: 'JINSI YA KUTUMIA', text: 'Chagua huduma kwa namba.\n0. Rudi', options: ['0'] },
  '4:2': { title: 'WASILIANA NASI', text: 'Muone mhudumu wa Soko Langu.\n0. Rudi', options: ['0'] },
};

function lanIps() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const item of list || []) {
      if (item.family === 'IPv4' && !item.internal) out.push(item.address);
    }
  }
  return [...new Set(out)];
}

function json(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(data),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-Pair-Token',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Cache-Control': 'no-store',
  });
  res.end(data);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', chunk => {
      raw += chunk;
      if (raw.length > 1024 * 1024) req.destroy();
    });
    req.on('end', () => {
      try { resolve(raw ? JSON.parse(raw) : {}); } catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

function authorized(req) { return req.headers['x-pair-token'] === TOKEN; }

function screenFor(session, code) {
  if (code === '*123#') return { ...menus['*123#'], path: [] };
  if (code === '0') {
    const parent = session.path.slice(0, -1);
    const parentKey = parent.length ? parent[parent.length - 1] : '*123#';
    const base = menus[parentKey] || menus['*123#'];
    return { ...base, path: parent };
  }
  const parentKey = session.path.length ? session.path[session.path.length - 1] : '*123#';
  const key = parentKey === '*123#' ? code : `${parentKey}:${code}`;
  if (menus[key]) return { ...menus[key], path: [...session.path, code] };
  return { title: 'SOKO LANGU', text: 'Chaguo si sahihi. Jaribu tena.\n0. Rudi', options: ['0'], path: session.path };
}

function pruneSessions() {
  const cutoff = Date.now() - 15 * 60 * 1000;
  for (const [id, s] of sessions) if (s.lastSeen < cutoff) sessions.delete(id);
}
setInterval(pruneSessions, 60 * 1000).unref();

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return json(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { ok: true, service: 'offline-ussd', version: 2 });
  if (req.method === 'GET' && url.pathname === '/pair-info') return json(res, 200, { ok: true, tokenRequired: true, service: 'Soko Langu Offline USSD', version: 2 });
  if (!authorized(req)) return json(res, 401, { ok: false, error: 'PAIR_TOKEN_REQUIRED' });

  try {
    if (req.method === 'POST' && url.pathname === '/pair') {
      const sessionId = crypto.randomUUID();
      sessions.set(sessionId, { createdAt: Date.now(), lastSeen: Date.now(), path: [], lastCode: null, events: [] });
      return json(res, 200, { ok: true, sessionId, message: 'PHONE_CONNECTED' });
    }

    if (req.method === 'POST' && url.pathname === '/ussd') {
      const body = await readBody(req);
      const session = sessions.get(body.sessionId);
      if (!session) return json(res, 404, { ok: false, error: 'SESSION_NOT_FOUND' });
      const code = String(body.code || '').trim();
      if (!code) return json(res, 400, { ok: false, error: 'CODE_REQUIRED' });
      session.lastSeen = Date.now();
      const screen = screenFor(session, code);
      session.lastCode = code;
      session.path = screen.path;
      return json(res, 200, { ok: true, sessionId: body.sessionId, status: 'CONTINUE', title: screen.title, text: screen.text, options: screen.options });
    }

    if (req.method === 'POST' && url.pathname === '/push') {
      const body = await readBody(req);
      const session = sessions.get(body.sessionId);
      if (!session) return json(res, 404, { ok: false, error: 'SESSION_NOT_FOUND' });
      session.lastSeen = Date.now();
      session.events.push({ id: crypto.randomUUID(), title: String(body.title || 'SOKO LANGU'), text: String(body.text || ''), at: Date.now() });
      return json(res, 200, { ok: true, status: 'PUSH_QUEUED' });
    }

    if (req.method === 'GET' && url.pathname === '/events') {
      const session = sessions.get(url.searchParams.get('sessionId'));
      if (!session) return json(res, 404, { ok: false, error: 'SESSION_NOT_FOUND' });
      session.lastSeen = Date.now();
      const events = session.events.splice(0, session.events.length);
      return json(res, 200, { ok: true, events });
    }

    if (req.method === 'GET' && url.pathname === '/status') return json(res, 200, { ok: true, sessions: sessions.size, service: 'offline-ussd' });
    return json(res, 404, { ok: false, error: 'NOT_FOUND' });
  } catch (err) {
    return json(res, 500, { ok: false, error: 'SERVER_ERROR', message: err.message });
  }
});

server.listen(PORT, HOST, () => {
  console.log('==============================================');
  console.log(' SOKO LANGU - OFFLINE USSD SERVER v2');
  console.log('==============================================');
  console.log(` Local:   http://127.0.0.1:${PORT}`);
  for (const ip of lanIps()) console.log(` PHONE:   http://${ip}:${PORT}`);
  console.log(` TOKEN:   ${TOKEN}`);
  console.log('');
  console.log('PC and Android phone must use the SAME Wi-Fi/router.');
  console.log('Internet is NOT required. Enter PHONE URL + TOKEN in the APK.');
  console.log('');
});

module.exports = { server, menus, TOKEN, lanIps };
