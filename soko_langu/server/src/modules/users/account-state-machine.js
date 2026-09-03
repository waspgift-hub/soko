/**
 * Account State Machine
 * 
 * States:
 *   USER_PENDING -> USER_ACTIVE -> USER_RESTRICTED -> USER_SUSPENDED -> USER_DELETION_PENDING -> USER_DELETED
 */

const ACCOUNT_STATES = {
  PENDING: 'pending',
  ACTIVE: 'active',
  RESTRICTED: 'restricted',
  SUSPENDED: 'suspended',
  DELETION_PENDING: 'deletion_pending',
  DELETED: 'deleted',
};

const TRANSITIONS = {
  [ACCOUNT_STATES.PENDING]: [ACCOUNT_STATES.ACTIVE, ACCOUNT_STATES.SUSPENDED, ACCOUNT_STATES.DELETION_PENDING],
  [ACCOUNT_STATES.ACTIVE]: [ACCOUNT_STATES.RESTRICTED, ACCOUNT_STATES.SUSPENDED, ACCOUNT_STATES.DELETION_PENDING],
  [ACCOUNT_STATES.RESTRICTED]: [ACCOUNT_STATES.ACTIVE, ACCOUNT_STATES.SUSPENDED, ACCOUNT_STATES.DELETION_PENDING],
  [ACCOUNT_STATES.SUSPENDED]: [ACCOUNT_STATES.ACTIVE, ACCOUNT_STATES.DELETION_PENDING],
  [ACCOUNT_STATES.DELETION_PENDING]: [ACCOUNT_STATES.DELETED, ACCOUNT_STATES.ACTIVE],
  [ACCOUNT_STATES.DELETED]: [],
};

// Who can trigger each transition
const TRANSITION_AUTH = {
  [ACCOUNT_STATES.ACTIVE]: { role: 'system', reason: 'email_verified_or_first_login' },
  [ACCOUNT_STATES.RESTRICTED]: { role: 'admin', reason: 'admin_restriction' },
  [ACCOUNT_STATES.SUSPENDED]: { role: 'admin', reason: 'admin_suspension' },
  [ACCOUNT_STATES.DELETION_PENDING]: { role: ['admin', 'user'], reason: 'user_request_or_admin_action' },
  [ACCOUNT_STATES.DELETED]: { role: ['admin', 'system'], reason: 'anonymization_complete_after_grace' },
};

// What a user in each state can do
const STATE_PERMISSIONS = {
  [ACCOUNT_STATES.PENDING]: {
    read: true,
    write: false,
    sell: false,
    buy: false,
    message: false,
    comment: false,
    withdraw: false,
  },
  [ACCOUNT_STATES.ACTIVE]: {
    read: true,
    write: true,
    sell: true,
    buy: true,
    message: true,
    comment: true,
    withdraw: true,
  },
  [ACCOUNT_STATES.RESTRICTED]: {
    read: true,
    write: true,
    sell: false,
    buy: true,
    message: false,
    comment: false,
    withdraw: false,
  },
  [ACCOUNT_STATES.SUSPENDED]: {
    read: false,
    write: false,
    sell: false,
    buy: false,
    message: false,
    comment: false,
    withdraw: false,
  },
  [ACCOUNT_STATES.DELETION_PENDING]: {
    read: true,
    write: false,
    sell: false,
    buy: false,
    message: false,
    comment: false,
    withdraw: false,
  },
  [ACCOUNT_STATES.DELETED]: {
    read: false,
    write: false,
    sell: false,
    buy: false,
    message: false,
    comment: false,
    withdraw: false,
  },
};

class AccountStateMachine {
  constructor(state) {
    this.currentState = state || ACCOUNT_STATES.PENDING;
  }

  canTransition(toState) {
    const allowed = TRANSITIONS[this.currentState] || [];
    return allowed.includes(toState);
  }

  canPerform(action) {
    const permissions = STATE_PERMISSIONS[this.currentState] || {};
    return permissions[action] === true;
  }

  transition(toState, { role, reason, actorId } = {}) {
    if (!this.canTransition(toState)) {
      throw new Error(`Invalid transition from ${this.currentState} to ${toState}`);
    }

    const auth = TRANSITION_AUTH[toState];
    if (!auth) {
      throw new Error(`No authorization defined for state ${toState}`);
    }

    const allowedRoles = Array.isArray(auth.role) ? auth.role : [auth.role];
    if (role && !allowedRoles.includes(role)) {
      throw new Error(`Role ${role} cannot transition to ${toState}`);
    }

    const oldState = this.currentState;
    this.currentState = toState;

    return {
      oldState,
      newState: toState,
      reason,
      actorId,
      timestamp: new Date().toISOString(),
    };
  }

  static getPermissions(state) {
    return STATE_PERMISSIONS[state] || {};
  }
}

module.exports = {
  ACCOUNT_STATES,
  AccountStateMachine,
  TRANSITIONS,
  STATE_PERMISSIONS,
};
