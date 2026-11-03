'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');
const { logAuditEvent } = require('./audit');
const rbac = require('./rbac');

const EMPLOYEES = 'company_employees';
const DEPARTMENTS = 'company_departments';
const LEAVE = 'company_leave_requests';

function db() { return getFirebaseFirestore(); }

async function listEmployees({ legalEntityId = '', department = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(EMPLOYEES).orderBy('created_at', 'desc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  if (department) q = q.where('department', '==', department);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function getEmployee(id) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const snap = await d.collection(EMPLOYEES).doc(id).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

async function createEmployee(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    firebase_uid: data.firebaseUid || '',
    display_name: data.displayName || '',
    legal_name: data.legalName || '',
    title: data.title || '',
    department: data.department || '',
    branch: data.branch || '',
    manager_uid: data.managerUid || '',
    employment_type: data.employmentType || 'employee',
    status: 'active',
    start_date: data.startDate || now.slice(0, 10),
    end_date: null,
    skills: data.skills || [],
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(EMPLOYEES).add(doc);
  await logAuditEvent({ actorUid, action: 'employee.create', targetType: 'employee', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function updateEmployee(id, patch, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const allowed = ['display_name', 'legal_name', 'title', 'department', 'branch', 'manager_uid', 'employment_type', 'status', 'end_date', 'skills'];
  const updates = { updated_at: now };
  for (const k of allowed) if (patch[k] !== undefined) updates[k] = patch[k];
  await d.collection(EMPLOYEES).doc(id).update(updates);
  await logAuditEvent({ actorUid, action: 'employee.update', targetType: 'employee', targetId: id, metadata: { fields: Object.keys(updates) } });
  return getEmployee(id);
}

async function listDepartments(legalEntityId = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(DEPARTMENTS).orderBy('name', 'asc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createDepartment(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    name: data.name,
    parent_id: data.parentId || '',
    head_uid: data.headUid || '',
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(DEPARTMENTS).add(doc);
  await logAuditEvent({ actorUid, action: 'department.create', targetType: 'department', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function listLeave({ employeeUid = '', status = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(LEAVE).orderBy('created_at', 'desc');
  if (employeeUid) q = q.where('employee_uid', '==', employeeUid);
  if (status) q = q.where('status', '==', status);
  const snap = await q.limit(200).get();
  return snap.docs.map((x) => ({ id: x.id, ...x.data() }));
}

async function createLeave(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    employee_uid: data.employeeUid,
    type: data.type || 'annual',
    start_date: data.startDate,
    end_date: data.endDate,
    reason: data.reason || '',
    status: 'submitted',
    approver_uid: '',
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(LEAVE).add(doc);
  await logAuditEvent({ actorUid, action: 'leave.submit', targetType: 'leave_request', targetId: ref.id });
  return { id: ref.id, ...doc };
}

async function decideLeave(id, decision, approverUid, reason = '') {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const status = decision === 'approve' ? 'approved' : 'rejected';
  await d.collection(LEAVE).doc(id).update({ status, approver_uid: approverUid, decision_reason: reason, updated_at: now });
  await logAuditEvent({ actorUid: approverUid, action: `leave.${status}`, targetType: 'leave_request', targetId: id, reason });
  const snap = await d.collection(LEAVE).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

module.exports = { listEmployees, getEmployee, createEmployee, updateEmployee, listDepartments, createDepartment, listLeave, createLeave, decideLeave };
