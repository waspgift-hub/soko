/**
 * Seller Activation State Machine
 * 
 * States:
 *   NOT_SELLER -> SELLER_MODE_REQUESTED -> SELLER_PROFILE_REQUIRED -> ELIGIBILITY_CHECK -> SELLER_ACTIVE
 *                                                                -> SELLER_PENDING_REVIEW -> SELLER_REJECTED
 */

const SELLER_STATES = {
  NOT_SELLER: 'not_seller',
  MODE_REQUESTED: 'requested',
  PROFILE_REQUIRED: 'profile_required',
  ELIGIBILITY_CHECK: 'eligibility_check',
  ACTIVE: 'active',
  PENDING_REVIEW: 'pending_review',
  REJECTED: 'rejected',
};

const TRANSITIONS = {
  [SELLER_STATES.NOT_SELLER]: [SELLER_STATES.MODE_REQUESTED],
  [SELLER_STATES.MODE_REQUESTED]: [SELLER_STATES.PROFILE_REQUIRED],
  [SELLER_STATES.PROFILE_REQUIRED]: [SELLER_STATES.ELIGIBILITY_CHECK],
  [SELLER_STATES.ELIGIBILITY_CHECK]: [SELLER_STATES.ACTIVE, SELLER_STATES.PENDING_REVIEW, SELLER_STATES.REJECTED],
  [SELLER_STATES.PENDING_REVIEW]: [SELLER_STATES.ACTIVE, SELLER_STATES.REJECTED],
  [SELLER_STATES.ACTIVE]: [SELLER_STATES.PENDING_REVIEW, SELLER_STATES.REJECTED],
  [SELLER_STATES.REJECTED]: [SELLER_STATES.MODE_REQUESTED],
};

class SellerStateMachine {
  constructor(state) {
    this.currentState = state || SELLER_STATES.NOT_SELLER;
  }

  canTransition(toState) {
    const allowed = TRANSITIONS[this.currentState] || [];
    return allowed.includes(toState);
  }

  transition(toState, { actorId, reason } = {}) {
    if (!this.canTransition(toState)) {
      throw new Error(`Invalid seller transition from ${this.currentState} to ${toState}`);
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

  static getEligibilityCriteria() {
    return [
      {
        field: 'storeName',
        required: true,
        description: 'Store name is required',
      },
      {
        field: 'storeSlug',
        required: true,
        description: 'Store slug is required',
      },
      {
        field: 'accountStatus',
        required: 'active',
        description: 'Account must be active',
      },
      {
        field: 'kycRequired',
        required: true,
        description: 'KYC verification required for high-value sellers',
      },
    ];
  }

  static checkEligibility(sellerProfile) {
    const criteria = SellerStateMachine.getEligibilityCriteria();
    const failures = [];

    for (const c of criteria) {
      const value = sellerProfile[c.field];
      if (c.required === true && !value) {
        failures.push(c.description);
      } else if (typeof c.required === 'string' && value !== c.required) {
        failures.push(c.description);
      }
    }

    return {
      pass: failures.length === 0,
      failures,
    };
  }
}

module.exports = {
  SELLER_STATES,
  SellerStateMachine,
  TRANSITIONS,
};
