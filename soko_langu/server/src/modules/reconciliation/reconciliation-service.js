const { getPrisma } = require('../../config/database');
const { clickpesaQueryPayments, clickpesaQueryPayouts } = require('../../../clickpesa');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function toBig(n) {
  try {
    return BigInt(Math.round(Number(n) || 0));
  } catch {
    return 0n;
  }
}

// Normalize provider records of unknown shape into {reference, amount, status}.
function normalizeProviderRecords(raw) {
  const list = Array.isArray(raw) ? raw : raw?.data || raw?.payments || raw?.payouts || [];
  return (Array.isArray(list) ? list : []).map((r) => ({
    reference: r.orderReference || r.order_reference || r.reference || r.id || null,
    amount: Number(r.amount || 0),
    status: String(r.status || '').toUpperCase(),
  }));
}

function isSuccessful(status) {
  return ['SUCCESS', 'SUCCESSFUL', 'PAID', 'COMPLETED'].includes(String(status || '').toUpperCase());
}

async function runReconciliation({ provider = 'clickpesa', periodStart, periodEnd }) {
  if (!periodStart || !periodEnd) throw httpError(400, 'periodStart and periodEnd required');
  const start = new Date(periodStart);
  const end = new Date(periodEnd);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || start >= end) {
    throw httpError(400, 'Invalid period');
  }
  const prisma = getPrisma();

  const [paidAgg, payoutAgg] = await Promise.all([
    prisma.payment.aggregate({
      where: { status: 'completed', createdAt: { gte: start, lt: end } },
      _sum: { amount: true },
    }),
    prisma.payoutTransaction.aggregate({
      where: { status: 'completed', createdAt: { gte: start, lt: end } },
      _sum: { amount: true },
    }),
  ]);
  const internalTotal = toBig(paidAgg._sum.amount) - toBig(payoutAgg._sum.amount);

  let providerRecords = [];
  const providerErrors = [];
  try {
    const [payments, payouts] = await Promise.all([
      clickpesaQueryPayments({}).catch((e) => {
        providerErrors.push(`payments: ${e.message}`);
        return [];
      }),
      clickpesaQueryPayouts({}).catch((e) => {
        providerErrors.push(`payouts: ${e.message}`);
        return [];
      }),
    ]);
    providerRecords = [...normalizeProviderRecords(payments), ...normalizeProviderRecords(payouts)];
  } catch (e) {
    providerErrors.push(e.message);
  }

  // Sum successful provider amounts inside the window is approximate when
  // the provider does not support date filters; record the method in notes.
  const providerTotal = providerRecords
    .filter((r) => isSuccessful(r.status))
    .reduce((sum, r) => sum + r.amount, 0);

  const difference = internalTotal - toBig(providerTotal);
  const row = await prisma.reconciliation.create({
    data: {
      periodStart: start,
      periodEnd: end,
      provider,
      internalTotal,
      providerTotal: toBig(providerTotal),
      difference,
      status: difference === 0n ? 'matched' : 'mismatched',
      notes:
        providerErrors.length > 0
          ? `provider errors: ${providerErrors.join('; ')}`
          : `compared ${providerRecords.length} provider records`,
    },
  });
  return row;
}

async function listReconciliations({ page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const [items, total] = await Promise.all([
    prisma.reconciliation.findMany({
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.reconciliation.count(),
  ]);
  return { items, pagination: { page: Number(page), limit: Number(limit), total } };
}

module.exports = { runReconciliation, listReconciliations };
