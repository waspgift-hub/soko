'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');

const MEMBERSHIPS = 'company_memberships';
const LEGAL_ENTITIES = 'company_legal_entities';
const EMPLOYEES = 'company_employees';
const DEPARTMENTS = 'company_departments';
const PROJECTS = 'company_projects';
const TASKS = 'company_tasks';
const MILESTONES = 'company_milestones';
const INVOICES = 'company_invoices';
const EXPENSES = 'company_expenses';
const LEAVE = 'company_leave_requests';
const AUDIT = 'company_audit_events';

function db() {
  return getFirebaseFirestore();
}

async function getOverview() {
  const d = db();
  if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');

  const [
    membershipsSnap,
    legalEntitiesSnap,
    employeesSnap,
    departmentsSnap,
    projectsSnap,
    tasksSnap,
    milestonesSnap,
    invoicesSnap,
    expensesSnap,
    pendingLeaveSnap,
    auditSnap,
  ] = await Promise.all([
    d.collection(MEMBERSHIPS).get(),
    d.collection(LEGAL_ENTITIES).get(),
    d.collection(EMPLOYEES).get(),
    d.collection(DEPARTMENTS).get(),
    d.collection(PROJECTS).get(),
    d.collection(TASKS).get(),
    d.collection(MILESTONES).get(),
    d.collection(INVOICES).get(),
    d.collection(EXPENSES).get(),
    d.collection(LEAVE).where('status', '==', 'submitted').get(),
    d.collection(AUDIT).orderBy('created_at', 'desc').limit(15).get(),
  ]);

  const tasks = tasksSnap.docs.map((x) => ({ id: x.id, ...x.data() }));
  const projects = projectsSnap.docs.map((x) => ({ id: x.id, ...x.data() }));
  const invoices = invoicesSnap.docs.map((x) => ({ id: x.id, ...x.data() }));
  const expenses = expensesSnap.docs.map((x) => ({ id: x.id, ...x.data() }));

  const now = new Date();
  const todayStr = now.toISOString().slice(0, 10);

  const tasksDueToday = tasks.filter((t) => (t.due_date || '') === todayStr).length;
  const tasksOverdue = tasks.filter((t) => {
    if (!t.due_date) return false;
    if (['completed', 'cancelled'].includes(t.status)) return false;
    return t.due_date < todayStr;
  }).length;
  const tasksInProgress = tasks.filter((t) => t.status === 'in_progress').length;
  const tasksBlocked = tasks.filter((t) => t.status === 'blocked').length;
  const tasksCompleted = tasks.filter((t) => t.status === 'completed').length;

  const projectsActive = projects.filter((p) => !['completed', 'cancelled', 'on_hold'].includes(p.status)).length;
  const projectsAtRisk = projects.filter((p) => p.health === 'at_risk' || p.risk_score >= 70).length;
  const projectsBlocked = projects.filter((p) => p.health === 'blocked').length;

  const invoicesDraft = invoices.filter((i) => i.status === 'draft').length;
  const invoicesSubmitted = invoices.filter((i) => i.status === 'submitted').length;
  const invoicesApproved = invoices.filter((i) => i.status === 'approved').length;
  const invoicesPosted = invoices.filter((i) => i.status === 'posted').length;
  const invoicesPaid = invoices.filter((i) => i.status === 'paid').length;

  const expensesSubmitted = expenses.filter((e) => e.status === 'submitted').length;
  const expensesApproved = expenses.filter((e) => e.status === 'approved').length;
  const expensesRejected = expenses.filter((e) => e.status === 'rejected').length;

  let invoiceTotalAr = 0;
  let invoiceTotalAp = 0;
  for (const inv of invoices) {
    const amt = Number(inv.amount || 0);
    if (inv.type === 'ap') invoiceTotalAp += amt;
    else invoiceTotalAr += amt;
  }

  let expenseTotal = 0;
  for (const ex of expenses) {
    if (ex.status === 'approved' || ex.status === 'paid') {
      expenseTotal += Number(ex.amount || 0);
    }
  }

  return {
    counts: {
      memberships: membershipsSnap.size,
      legal_entities: legalEntitiesSnap.size,
      employees: employeesSnap.size,
      departments: departmentsSnap.size,
      projects: projectsSnap.size,
      tasks: tasksSnap.size,
      milestones: milestonesSnap.size,
      invoices: invoicesSnap.size,
      expenses: expensesSnap.size,
      pending_leave: pendingLeaveSnap.size,
    },
    tasks: {
      due_today: tasksDueToday,
      overdue: tasksOverdue,
      in_progress: tasksInProgress,
      blocked: tasksBlocked,
      completed: tasksCompleted,
    },
    projects: {
      active: projectsActive,
      at_risk: projectsAtRisk,
      blocked: projectsBlocked,
    },
    finance: {
      invoices: {
        draft: invoicesDraft,
        submitted: invoicesSubmitted,
        approved: invoicesApproved,
        posted: invoicesPosted,
        paid: invoicesPaid,
        total_ar: invoiceTotalAr,
        total_ap: invoiceTotalAp,
      },
      expenses: {
        submitted: expensesSubmitted,
        approved: expensesApproved,
        rejected: expensesRejected,
        total_approved: expenseTotal,
      },
    },
    pending_approvals: {
      leave: pendingLeaveSnap.size,
      invoices_submitted: invoicesSubmitted,
      expenses_submitted: expensesSubmitted,
    },
    recent_audit: auditSnap.docs.map((x) => ({ id: x.id, ...x.data() })),
    generated_at: now.toISOString(),
  };
}

module.exports = { getOverview };
