'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');
const { logAuditEvent } = require('./audit');

const PROJECTS = 'company_projects';
const MILESTONES = 'company_milestones';
const TASKS = 'company_tasks';
const TASK_HISTORY = 'company_task_history';

function db() { return getFirebaseFirestore(); }

async function listProjects({ legalEntityId = '', department = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(PROJECTS).orderBy('created_at', 'desc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  if (department) q = q.where('department', '==', department);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function getProject(id) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const snap = await d.collection(PROJECTS).doc(id).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

async function createProject(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    department: data.department || '',
    name: data.name,
    code: data.code || '',
    summary: data.summary || '',
    objectives: data.objectives || [],
    sponsor_uid: data.sponsorUid || '',
    manager_uid: data.managerUid || '',
    status: 'draft',
    priority: data.priority || 'medium',
    health: 'on_track',
    risk_score: 0,
    start_date: data.startDate || now.slice(0, 10),
    target_deadline: data.targetDeadline || '',
    actual_completion: null,
    budget_approved: Number(data.budgetApproved || 0),
    budget_committed: 0,
    budget_actual: 0,
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(PROJECTS).add(doc);
  await logAuditEvent({ actorUid, action: 'project.create', targetType: 'project', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function updateProject(id, patch, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const allowed = ['name', 'summary', 'objectives', 'status', 'priority', 'health', 'risk_score', 'target_deadline', 'actual_completion', 'budget_approved', 'budget_committed', 'budget_actual', 'manager_uid', 'sponsor_uid', 'department'];
  const updates = { updated_at: now };
  for (const k of allowed) if (patch[k] !== undefined) updates[k] = patch[k];
  await d.collection(PROJECTS).doc(id).update(updates);
  await logAuditEvent({ actorUid, action: 'project.update', targetType: 'project', targetId: id, metadata: { fields: Object.keys(updates) } });
  return getProject(id);
}

async function listMilestones(projectId) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const snap = await d.collection(MILESTONES).where('project_id', '==', projectId).orderBy('due_date', 'asc').get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createMilestone(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    project_id: data.projectId,
    name: data.name,
    due_date: data.dueDate || '',
    status: 'pending',
    acceptance_criteria: data.acceptanceCriteria || '',
    accepted_by: '',
    accepted_at: null,
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(MILESTONES).add(doc);
  await logAuditEvent({ actorUid, action: 'milestone.create', targetType: 'milestone', targetId: ref.id });
  return { id: ref.id, ...doc };
}

async function acceptMilestone(id, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  await d.collection(MILESTONES).doc(id).update({ status: 'accepted', accepted_by: actorUid, accepted_at: now, updated_at: now });
  await logAuditEvent({ actorUid, action: 'milestone.accept', targetType: 'milestone', targetId: id });
  const snap = await d.collection(MILESTONES).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

async function listTasks({ projectId = '', ownerUid = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(TASKS).orderBy('created_at', 'desc');
  if (projectId) q = q.where('project_id', '==', projectId);
  if (ownerUid) q = q.where('owner_uid', '==', ownerUid);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(300).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createTask(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    project_id: data.projectId || '',
    milestone_id: data.milestoneId || '',
    parent_task_id: data.parentTaskId || '',
    title: data.title,
    description: data.description || '',
    owner_uid: data.ownerUid || '',
    reviewer_uid: data.reviewerUid || '',
    status: 'assigned',
    priority: data.priority || 'medium',
    due_date: data.dueDate || '',
    estimate_hours: Number(data.estimateHours || 0),
    actual_hours: 0,
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(TASKS).add(doc);
  await d.collection(TASK_HISTORY).add({ task_id: ref.id, from_status: '', to_status: 'assigned', actor_uid: actorUid, reason: 'created', created_at: now });
  await logAuditEvent({ actorUid, action: 'task.create', targetType: 'task', targetId: ref.id });
  return { id: ref.id, ...doc };
}

async function transitionTask(id, newStatus, actorUid, reason = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const snap = await d.collection(TASKS).doc(id).get();
  if (!snap.exists) throw new Error('TASK_NOT_FOUND');
  const from = snap.data().status;
  const allowed = ['draft', 'assigned', 'accepted', 'in_progress', 'blocked', 'review', 'completed', 'cancelled'];
  if (!allowed.includes(newStatus)) throw new Error('INVALID_STATUS');
  await d.collection(TASKS).doc(id).update({ status: newStatus, updated_at: now });
  await d.collection(TASK_HISTORY).add({ task_id: id, from_status: from, to_status: newStatus, actor_uid: actorUid, reason: reason || '', created_at: now });
  await logAuditEvent({ actorUid, action: `task.transition.${newStatus}`, targetType: 'task', targetId: id, reason, metadata: { from, to: newStatus } });
  const updated = await d.collection(TASKS).doc(id).get();
  return { id: updated.id, ...updated.data() };
}

module.exports = { listProjects, getProject, createProject, updateProject, listMilestones, createMilestone, acceptMilestone, listTasks, createTask, transitionTask };
