/**
 * User Settings State Machine
 * 
 * Flow: SETTINGS_VIEW -> LOAD_SERVER_PROFILE -> USER_EDITS -> CLIENT_VALIDATE ->
 *       AUTHENTICATED_WRITE -> SERVER_AUTHORIZATION -> DB_TRANSACTION ->
 *       AUDIT -> CACHE_REFRESH -> SETTINGS_UPDATED
 */

const SETTINGS_PHASES = {
  VIEW: 'view',
  LOAD_SERVER: 'load_server',
  USER_EDITS: 'user_edits',
  CLIENT_VALIDATE: 'client_validate',
  AUTHENTICATED_WRITE: 'authenticated_write',
  SERVER_AUTHORIZATION: 'server_authorization',
  DB_TRANSACTION: 'db_transaction',
  AUDIT: 'audit',
  CACHE_REFRESH: 'cache_refresh',
  UPDATED: 'updated',
};

const SETTINGS_DOMAINS = [
  'profile',
  'security',
  'privacy',
  'notifications',
  'shopping',
  'selling',
  'payments',
  'language_region',
  'accessibility',
  'data_deletion',
];

const DOMAIN_VALIDATORS = {
  profile: ['displayName', 'username', 'bio', 'avatarUrl'],
  security: ['twoFactorEnabled', 'emailVerified', 'phoneVerified'],
  privacy: ['showEmail', 'showPhone', 'showLocation', 'profileVisibility'],
  notifications: ['pushEnabled', 'emailEnabled', 'smsEnabled', 'types'],
  shopping: ['defaultAddressId', 'preferredShipping', 'savedCards'],
  selling: ['storeName', 'storeDescription', 'returnsPolicy'],
  payments: ['defaultPayoutMethod', 'currencyPreference'],
  language_region: ['preferredLanguage', 'preferredCurrency', 'timezone', 'smsLangCode'],
  accessibility: ['fontScale', 'highContrast', 'reduceMotion'],
  data_deletion: ['deletionRequested', 'dataExportRequested'],
};

class SettingsStateMachine {
  constructor(domain) {
    if (!DOMAIN_VALIDATORS[domain]) {
      throw new Error(`Invalid settings domain: ${domain}`);
    }
    this.domain = domain;
    this.phase = SETTINGS_PHASES.VIEW;
    this.history = [];
  }

  transition(toPhase, metadata = {}) {
    this.history.push({
      from: this.phase,
      to: toPhase,
      metadata,
      timestamp: new Date().toISOString(),
    });
    this.phase = toPhase;
    return this.phase;
  }

  validate(changes) {
    const validFields = DOMAIN_VALIDATORS[this.domain];
    const invalidFields = Object.keys(changes).filter(field => !validFields.includes(field));
    return {
      valid: invalidFields.length === 0,
      invalidFields,
    };
  }

  static getDomains() {
    return SETTINGS_DOMAINS;
  }

  static getValidFields(domain) {
    return DOMAIN_VALIDATORS[domain] || [];
  }
}

module.exports = {
  SETTINGS_PHASES,
  SETTINGS_DOMAINS,
  SettingsStateMachine,
  DOMAIN_VALIDATORS,
};
