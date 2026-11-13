'use strict';

// Deterministic admin briefing from already-authorized dashboard/metrics.
// Optional Groq wording never invents numbers; if the model is unavailable
// the same facts are returned as a template.

function toNum(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function buildFacts({ kpis = {}, metrics = {}, generatedAt }) {
  return {
    period: 'today_vs_store_totals',
    generatedAt: generatedAt || new Date().toISOString(),
    users: toNum(kpis.users),
    newUsersToday: toNum(kpis.newUsersToday),
    orders: toNum(kpis.orders),
    completedOrders: toNum(kpis.completedOrders),
    products: toNum(kpis.products),
    commissionRevenueTzs: toNum(kpis.commissionRevenue),
    escrowHeldTzs: toNum(kpis.escrowHeld),
    activeDisputes: toNum(kpis.activeDisputes),
    gmvTzs: toNum(metrics.gmv),
    withdrawalsPending: toNum(metrics.withdrawalsPending),
    disputesOpen: toNum(metrics.disputesOpen ?? kpis.activeDisputes),
    sources: ['adminService.getDashboard', 'adminService.getMetrics'],
    notes: [
      'Counts prefer the higher of store and Firestore overlays when both exist.',
      'Missing provider data is omitted rather than treated as zero activity.',
    ],
  };
}

function templateSummary(facts) {
  const lines = [
    `Ripoti ya kiutendaji (${facts.generatedAt}).`,
    `Watumiaji ${facts.users} (wapya leo ${facts.newUsersToday}).`,
    `Maagizo ${facts.orders}, yaliyokamilika ${facts.completedOrders}.`,
    `Bidhaa ${facts.products}. Tume TSh ${facts.commissionRevenueTzs.toLocaleString('en-TZ')}.`,
    `Escrow inayoshikiliwa TSh ${facts.escrowHeldTzs.toLocaleString('en-TZ')}.`,
    `Migogoro wazi ${facts.disputesOpen}; withdrawals zinazosubiri ${facts.withdrawalsPending}.`,
  ];
  const actions = [];
  if (facts.disputesOpen > 0) actions.push('Kagua migogoro wazi kabla ya kazi nyingine.');
  if (facts.withdrawalsPending > 0) actions.push('Thibitisha withdrawals kupitia moduli ya fedha tu.');
  if (facts.newUsersToday === 0 && facts.orders === 0) {
    actions.push('Hakuna shughuli mpya iliyothibitishwa katika vipimo vilivyopatikana.');
  }
  return {
    facts,
    summary: lines.join(' '),
    recommendedActions: actions,
    aiUsed: false,
  };
}

function parseModelText(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (!trimmed || /as an ai|i cannot access/i.test(trimmed)) return null;
  return trimmed.slice(0, 2000);
}

async function maybePolish(facts, completeChat) {
  const base = templateSummary(facts);
  if (typeof completeChat !== 'function') return base;
  try {
    const prompt = [
      'You are Soko Vibe admin briefing. Use ONLY these facts. Do not invent numbers.',
      'Reply in Swahili, 4 short sentences, then a bullet list of next actions from the facts.',
      JSON.stringify(facts),
    ].join('\n');
    const raw = await completeChat(prompt);
    const text = parseModelText(raw);
    if (!text) return base;
    return { ...base, summary: text, aiUsed: true };
  } catch (_) {
    return base;
  }
}

module.exports = { buildFacts, templateSummary, maybePolish };
