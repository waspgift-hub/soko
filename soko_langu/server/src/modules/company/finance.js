'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');
const { logAuditEvent } = require('./audit');

const ACCOUNTS = 'company_accounts';
const BUDGETS = 'company_budgets';
const INVOICES = 'company_invoices';
const EXPENSES = 'company_expenses';
const JOURNALS = 'company_journal_entries';
const PAYMENTS = 'company_payments';

function db() { return getFirebaseFirestore(); }

// ---- Chart of accounts ----
async function listAccounts(legalEntityId = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(ACCOUNTS).orderBy('code', 'asc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  const snap = await q.limit(500).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createAccount(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    code: data.code,
    name: data.name,
    type: data.type || 'expense', // asset|liability|equity|income|expense
    parent_id: data.parentId || '',
    currency: data.currency || 'TZS',
    active: true,
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(ACCOUNTS).add(doc);
  await logAuditEvent({ actorUid, action: 'account.create', targetType: 'account', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

// ---- Budgets ----
async function listBudgets({ legalEntityId = '', department = '', projectId = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(BUDGETS).orderBy('created_at', 'desc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  if (department) q = q.where('department', '==', department);
  if (projectId) q = q.where('project_id', '==', projectId);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createBudget(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    department: data.department || '',
    project_id: data.projectId || '',
    account_id: data.accountId || '',
    period_start: data.periodStart,
    period_end: data.periodEnd,
    amount: Number(data.amount || 0),
    currency: data.currency || 'TZS',
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(BUDGETS).add(doc);
  await logAuditEvent({ actorUid, action: 'budget.create', targetType: 'budget', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

// ---- Invoices (AR/AP) ----
async function listInvoices({ legalEntityId = '', type = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(INVOICES).orderBy('created_at', 'desc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  if (type) q = q.where('type', '==', type);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createInvoice(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    type: data.type || 'ar', // ar | ap
    number: data.number || '',
    counterparty: data.counterparty || '',
    counterparty_ref: data.counterpartyRef || '',
    amount: Number(data.amount || 0),
    currency: data.currency || 'TZS',
    due_date: data.dueDate || '',
    status: 'draft',
    notes: data.notes || '',
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(INVOICES).add(doc);
  await logAuditEvent({ actorUid, action: 'invoice.create', targetType: 'invoice', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function updateInvoiceStatus(id, status, actorUid, reason = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const allowed = ['draft', 'submitted', 'approved', 'posted', 'paid', 'cancelled'];
  if (!allowed.includes(status)) throw new Error('INVALID_STATUS');
  const now = new Date().toISOString();
  await d.collection(INVOICES).doc(id).update({ status, updated_at: now, updated_by: actorUid });
  await logAuditEvent({ actorUid, action: `invoice.${status}`, targetType: 'invoice', targetId: id, reason });
  const snap = await d.collection(INVOICES).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

// ---- Expenses ----
async function listExpenses({ legalEntityId = '', department = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(EXPENSES).orderBy('created_at', 'desc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  if (department) q = q.where('department', '==', department);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createExpense(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    department: data.department || '',
    project_id: data.projectId || '',
    account_id: data.accountId || '',
    amount: Number(data.amount || 0),
    currency: data.currency || 'TZS',
    description: data.description || '',
    receipt_url: data.receiptUrl || '',
    status: 'submitted',
    submitted_by: actorUid,
    approved_by: '',
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(EXPENSES).add(doc);
  await logAuditEvent({ actorUid, action: 'expense.submit', targetType: 'expense', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function decideExpense(id, decision, actorUid, reason = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const status = decision === 'approve' ? 'approved' : 'rejected';
  await d.collection(EXPENSES).doc(id).update({ status, approved_by: actorUid, decision_reason: reason, updated_at: now });
  await logAuditEvent({ actorUid, action: `expense.${status}`, targetType: 'expense', targetId: id, reason });
  const snap = await d.collection(EXPENSES).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

// ---- Journal entries (double-entry) ----
async function listJournals({ legalEntityId = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(JOURNALS).orderBy('created_at', 'desc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(100).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createJournal(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const lines = Array.isArray(data.lines) ? data.lines : [];
  // Validate balance: sum debits == sum credits per currency.
  const totals = {};
  for (const ln of lines) {
    const cur = ln.currency || data.currency || 'TZS';
    totals[cur] = totals[cur] || { debit: 0, credit: 0 };
    totals[cur].debit += Number(ln.debit || 0);
    totals[cur].credit += Number(ln.credit || 0);
  }
  for (const cur of Object.keys(totals)) {
    if (Math.abs(totals[cur].debit - totals[cur].credit) > 0.0001) {
      throw new Error(`UNBALANCED_JOURNAL:${cur}`);
    }
  }
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    date: data.date || now.slice(0, 10),
    description: data.description || '',
    currency: data.currency || 'TZS',
    status: 'draft',
    lines,
    idempotency_key: data.idempotencyKey || '',
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(JOURNALS).add(doc);
  await logAuditEvent({ actorUid, action: 'journal.create', targetType: 'journal', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function postJournal(id, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  await d.collection(JOURNALS).doc(id).update({ status: 'posted', posted_by: actorUid, posted_at: now, updated_at: now });
  await logAuditEvent({ actorUid, action: 'journal.post', targetType: 'journal', targetId: id });
  const snap = await d.collection(JOURNALS).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

async function reverseJournal(id, actorUid, reason = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  await d.collection(JOURNALS).doc(id).update({ status: 'reversed', reversed_by: actorUid, reversed_at: now, reversal_reason: reason, updated_at: now });
  await logAuditEvent({ actorUid, action: 'journal.reverse', targetType: 'journal', targetId: id, reason });
  const snap = await d.collection(JOURNALS).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

// ---- Payments ----
async function recordPayment(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    invoice_id: data.invoiceId || '',
    amount: Number(data.amount || 0),
    currency: data.currency || 'TZS',
    method: data.method || 'bank',
    reference: data.reference || '',
    date: data.date || now.slice(0, 10),
    created_by: actorUid,
    created_at: now,
  };
  const ref = await d.collection(PAYMENTS).add(doc);
  await logAuditEvent({ actorUid, action: 'payment.record', targetType: 'payment', targetId: ref.id });
  return { id: ref.id, ...doc };
}

async function listPayments(invoiceId = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(PAYMENTS).orderBy('created_at', 'desc');
  if (invoiceId) q = q.where('invoice_id', '==', invoiceId);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

module.exports = {
  listAccounts, createAccount,
  listBudgets, createBudget,
  listInvoices, createInvoice, updateInvoiceStatus,
  listExpenses, createExpense, decideExpense,
  listJournals, createJournal, postJournal, reverseJournal,
  recordPayment, listPayments,
};
