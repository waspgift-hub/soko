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
  '*123#': {
    title: 'SOKO LANGU',
    text: '1. Nunua\n2. Uza bidhaa\n3. Akaunti\n4. Msaada',
    options: ['1', '2', '3', '4'],
  },
  '1': { title: 'Nunua', text: '1. Bidhaa mpya\n2. Tafuta bidhaa\n0. Rudi', options: ['1', '2', '0'] },
  '2': { title: 'Uza bidhaa', text: '1. Ongeza bidhaa\n2. Oda zangu\n0. Rudi', options: ['1', '2', '0'] },
  '3': { title: 'Akaunti', text: '1. Salio\n2. Wasifu\n0. Rudi', options: ['1', '2', '0'] },
  '4': { title: 'Msaada', text: 'Wasiliana na Soko Langu support.\n0. Rudi', options: ['0'] },
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

function authorized(req) {
  return req.headers['x-pair-token'] === TOKEN;
}

function menuFor(code, stack) {
  if (code === '*123#') return { ...menus['*123#'], stack: [] };
  if (code === '0') return { ...menus['*123#'], stack: [] };
  if (menus[code]) return { ...menus[code], stack: [...stack, code] };
  return { title: 'SOKO LANGU', text: 'Chaguo si sahihi.\n0. Rudi', options: ['0'], stack };
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return json(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    return json(res, 200, { ok: true, service: 'offline-ussd', version: 1 });
  }

  if (req.method === 'GET' && url.pathname === '/pair-info') {
    return json(res, 200, { ok: true, tokenRequired: true, service: 'Soko Langu Offline USSD' });
  }

  if (!authorized(req)) return json(res, 401, { ok: false, error: 'PAIR_TOKEN_REQUIRED' });

  try {
    if (req.method === 'POST' && url.pathname === '/pair') {
      const sessionId = crypto.randomUUID();
      sessions.set(sessionId, { createdAt: Date.now(), stack: [], lastCode: null });
      return json(res, 200, { ok: true, sessionId, message: 'PHONE_CONNECTED' });
    }

    if (req.method === 'POST' && url.pathname === '/ussd') {
      const body = await readBody(req);
      const session = sessions.get(body.sessionId);
      if (!session) return json(res, 404, { ok: false, error: 'SESSION_NOT_FOUND' });
      const code = String(body.code || '').trim();
      if (!code) return json(res, 400, { ok: false, error: 'CODE_REQUIRED' });
      const screen = menuFor(code, session.stack);
      session.lastCode = code;
      session.stack = screen.stack;
      return json(res, 200, {
        ok: true,
        sessionId: body.sessionId,
        status: 'CONTINUE',
        title: screen.title,
        text: screen.text,
        options: screen.options,
      });
    }

    if (req.method === 'POST' && url.pathname === '/push') {
      const body = await readBody(req);
      const session = sessions.get(body.sessionId);
      if (!session) return json(res, 404, { ok: false, error: 'SESSION_NOT_FOUND' });
      return json(res, 200, { ok: true, status: 'PUSHED', text: String(body.text || '') });
    }

    if (req.method === 'GET' && url.pathname === '/status') {
      return json(res, 200, { ok: true, sessions: sessions.size });
    }

    return json(res, 404, { ok: false, error: 'NOT_FOUND' });
  } catch (err) {
    return json(res, 500, { ok: false, error: 'SERVER_ERROR', message: err.message });
  }
});

server.listen(PORT, HOST, () => {
  console.log('==============================================');
  console.log(' SOKO LANGU - OFFLINE USSD SERVER');
  console.log('==============================================');
  console.log(` Local:   http://127.0.0.1:${PORT}`);
  for (const ip of lanIps()) console.log(` PHONE:   http://${ip}:${PORT}`);
  console.log(` TOKEN:   ${TOKEN}`);
  console.log('');
  console.log('Connect the PC and Android phone to the SAME Wi-Fi/router.');
  console.log('No internet is required. Enter the PHONE URL + TOKEN in the APK.');
  console.log('Press Ctrl+C to stop.');
});

module.exports = { server, menus, TOKEN, lanIps };
