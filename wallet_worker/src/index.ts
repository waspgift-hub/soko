export interface Env {
  DB: D1Database;
  MONGIKE_API_KEY: string;
  MONGIKE_BASE_URL: string;
  MONGIKE_COLLECTION_PATH: string;
  MONGIKE_WEBHOOK_TOKEN: string;
  WALLET_CLIENT_TOKEN: string;
}

const json = (x: unknown, status = 200) => new Response(JSON.stringify(x), {
  status,
  headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' },
});
const id = () => crypto.randomUUID();
const clientAuth = (r: Request, e: Env) => {
  const h = r.headers.get('authorization') || '';
  return !!e.WALLET_CLIENT_TOKEN && h === `Bearer ${e.WALLET_CLIENT_TOKEN}`;
};
const webhookAuth = (u: URL, e: Env) =>
  !!e.MONGIKE_WEBHOOK_TOKEN && u.searchParams.get('token') === e.MONGIKE_WEBHOOK_TOKEN;

export default {
  async fetch(r: Request, e: Env): Promise<Response> {
    if (r.method === 'OPTIONS') return new Response(null, {
      headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
        'access-control-allow-headers': 'content-type,authorization',
      },
    });

    const u = new URL(r.url);

    // Mongike v3 webhook contract: order_id, payment_status, reference.
    if (u.pathname === '/webhooks/mongike' && r.method === 'POST') {
      if (!webhookAuth(u, e)) return json({ error: 'Unauthorized' }, 401);
      try {
        const raw = await r.text();
        let b: any;
        try { b = JSON.parse(raw); } catch { return json({ ok: true }); }

        const orderId = String(b.order_id ?? '');
        const state = String(b.payment_status ?? '').toUpperCase();
        const reference = String(b.reference ?? orderId);
        if (!orderId) return json({ error: 'Missing order_id' }, 400);

        const p = await e.DB.prepare('SELECT * FROM payments WHERE id=? OR order_id=? LIMIT 1')
          .bind(orderId, orderId).first<any>();
        if (!p) return json({ ok: true });

        if (state === 'COMPLETED') {
          // The unique ledger index makes repeated Mongike callbacks harmless.
          const w = await e.DB.prepare('SELECT balance_tzs FROM wallets WHERE id=?')
            .bind(p.wallet_id).first<{ balance_tzs: number }>();
          const before = w?.balance_tzs ?? 0;
          const after = before + p.amount_tzs;
          const ledgerId = id();
          const result = await e.DB.prepare(
            'INSERT OR IGNORE INTO ledger(id,wallet_id,payment_id,type,amount_tzs,balance_after,reference) VALUES(?,?,?,?,?,?,?)'
          ).bind(ledgerId, p.wallet_id, p.id, 'DEPOSIT', p.amount_tzs, after, reference).run();

          if ((result.meta?.changes ?? 0) > 0) {
            await e.DB.batch([
              e.DB.prepare('UPDATE wallets SET balance_tzs=?,updated_at=CURRENT_TIMESTAMP WHERE id=?')
                .bind(after, p.wallet_id),
              e.DB.prepare('UPDATE payments SET status=?,reference=?,updated_at=CURRENT_TIMESTAMP WHERE id=?')
                .bind('SUCCESS', reference, p.id),
            ]);
          }
        } else if (['FAILED', 'CANCELLED', 'EXPIRED'].includes(state)) {
          await e.DB.prepare(
            "UPDATE payments SET status=?,reference=?,updated_at=CURRENT_TIMESTAMP WHERE id=? AND status='PENDING'"
          ).bind(state, reference, p.id).run();
        }
        return json({ ok: true });
      } catch (err) {
        return json({ error: 'Webhook error', detail: String(err) }, 500);
      }
    }

    if (!clientAuth(r, e)) return json({ error: 'Unauthorized' }, 401);

    try {
      if (u.pathname === '/wallet/balance' && r.method === 'GET') {
        await e.DB.prepare('INSERT OR IGNORE INTO wallets(id,balance_tzs) VALUES(?,0)').bind('owner').run();
        const w = await e.DB.prepare('SELECT balance_tzs AS balance FROM wallets WHERE id=?')
          .bind('owner').first<{ balance: number }>();
        return json({ balance: w?.balance ?? 0, currency: 'TZS' });
      }

      if (u.pathname === '/wallet/deposit' && r.method === 'POST') {
        const b = await r.json() as { amount: number; phone: string; provider: string };
        if (!Number.isInteger(b.amount) || b.amount < 500 || !/^255[67]\d{8}$/.test(b.phone) || !b.provider) {
          return json({ error: 'Invalid deposit. Use phone format 2557XXXXXXXX/2556XXXXXXXX.' }, 400);
        }
        await e.DB.prepare('INSERT OR IGNORE INTO wallets(id,balance_tzs) VALUES(?,0)').bind('owner').run();
        const pid = id();
        const orderId = pid;
        await e.DB.prepare(
          'INSERT INTO payments(id,order_id,wallet_id,amount_tzs,phone,provider,status) VALUES(?,?,?,?,?,?,?)'
        ).bind(pid, orderId, 'owner', b.amount, b.phone, b.provider, 'PENDING').run();

        const base = (e.MONGIKE_BASE_URL || 'https://mongike.com/api/v1').replace(/\/$/, '');
        const path = e.MONGIKE_COLLECTION_PATH || '/payments/mobile-money/tanzania';
        if (!e.MONGIKE_API_KEY || !e.MONGIKE_WEBHOOK_TOKEN) {
          return json({ error: 'Mongike server credentials are not configured', paymentId: pid }, 503);
        }
        const webhookUrl = `${new URL(r.url).origin}/webhooks/mongike?token=${encodeURIComponent(e.MONGIKE_WEBHOOK_TOKEN)}`;
        const payload = {
          order_id: orderId,
          amount: b.amount,
          buyer_phone: b.phone,
          webhook_url: webhookUrl,
        };
        const mr = await fetch(`${base}${path}`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'x-api-key': e.MONGIKE_API_KEY },
          body: JSON.stringify(payload),
        });
        const text = await mr.text();
        let data: any;
        try { data = JSON.parse(text); } catch { data = { raw: text }; }
        if (!mr.ok) {
          await e.DB.prepare("UPDATE payments SET status='FAILED',updated_at=CURRENT_TIMESTAMP WHERE id=?")
            .bind(pid).run();
          return json({ error: 'Mongike rejected payment', paymentId: pid, providerResponse: data }, 502);
        }
        const mongikeId = typeof data === 'object' && data !== null
          ? String(data.id ?? data.payment_id ?? data.reference ?? '') : '';
        await e.DB.prepare('UPDATE payments SET mongike_id=?,updated_at=CURRENT_TIMESTAMP WHERE id=?')
          .bind(mongikeId || null, pid).run();
        return json({ paymentId: pid, status: 'PENDING', message: 'Payment request sent. Approve the prompt on your phone.', providerResponse: data }, 202);
      }

      if (u.pathname.startsWith('/wallet/payment/') && r.method === 'GET') {
        const pid = decodeURIComponent(u.pathname.split('/').pop() || '');
        const p = await e.DB.prepare(
          'SELECT id,amount_tzs AS amount,provider,status,mongike_id,reference,created_at,updated_at FROM payments WHERE id=?'
        ).bind(pid).first();
        return p ? json(p) : json({ error: 'Payment not found' }, 404);
      }

      if (u.pathname === '/wallet/transactions' && r.method === 'GET') {
        const rows = await e.DB.prepare(
          'SELECT id,type,amount_tzs AS amount,balance_after,reference,created_at FROM ledger WHERE wallet_id=? ORDER BY created_at DESC LIMIT 50'
        ).bind('owner').all();
        return json({ transactions: rows.results });
      }
      return json({ error: 'Not found' }, 404);
    } catch (err) {
      return json({ error: 'Server error', detail: String(err) }, 500);
    }
  },
};
