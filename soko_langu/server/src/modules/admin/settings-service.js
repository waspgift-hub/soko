// Platform settings store (admin panel "Mipangilio").
//
// Persisted as a single Firestore document `app_settings/admin_settings`, the
// same document family already used for the flash-sale push cooldown. That
// keeps settings cluster-wide across instances, needs no Prisma model and no
// Postgres migration. When Firestore is unavailable (local/dev) the service
// falls back to an in-memory copy so the panel stays fully usable.
const { getFirebaseFirestore } = require('../../config/firebase');

const SETTINGS_COLLECTION = 'app_settings';
const SETTINGS_DOC = 'admin_settings';

// Fields that are returned to the browser only as a masked marker
// ('******' when set, '' when empty) so secrets never reach the SPA bundle.
const SECRET_FIELDS = new Set([
  'smtpPass','smtpUser','firebaseServiceAccountJson','s3SecretKey',
  's3AccessKey','stripeSecretKey','paypalSecretKey','clickpesaSecretKey',
  'azamPaySecretKey','selcomSecretKey','twilioAuthToken','smsApiKey',
  'twilioAccountSid','twilioFrom','oauthGoogleClientSecret','oauthFbAppSecret',
]);

// Defaults for every group the Settings section manages. Secrets default to
// empty strings so a pristine Firestore doc never claims a secret is set.
const DEFAULTS = {
  general: {
    platformName: 'Soko Vibe',
    tagline: 'Nunua na Uza kwa Usalama',
    logoUrl: '',
    timezone: 'Africa/Dar_es_Salaam',
    language: 'sw',
    dateFormat: 'short',
    timeFormat: '24h',
    adminEmail: '',
    supportEmail: '',
    supportPhone: '',
  },
  registrationAndAuth: {
    allowRegistration: true,
    allowSellerSignup: true,
    defaultUserRole: 'buyer',
    requireEmailVerification: true,
    requirePhoneVerification: false,
    enable2FA: false,
    sessionTimeoutMinutes: 60,
  },
  paymentsAndCurrency: {
    currency: 'TZS',
    taxRatePct: 0,
    platformCommissionPct: 0,
    enableEscrow: true,
    escrowReleaseDays: 7,
    primaryGateway: 'clickpesa',
    gateways: {
      clickpesa: { enabled: true, merchantId: '', apiKey: '', secretKey: '' },
      azamPay: { enabled: false, merchantId: '', apiKey: '', secretKey: '' },
      selcom: { enabled: false, merchantId: '', apiKey: '', secretKey: '' },
      stripe: { enabled: false, secretKey: '' },
      paypal: { enabled: false, clientId: '', secretKey: '' },
    },
  },
  emailNotifications: {
    provider: 'smtp',
    smtpHost: '',
    smtpPort: 587,
    smtpSecure: false,
    smtpUser: '',
    smtpPass: '',
    fromEmail: '',
    fromName: 'Soko Vibe',
    signatures: { buyer: '', seller: '' },
  },
  integrations: {
    analyticsId: '',
    pixelId: '',
    s3Bucket: '',
    oauth: {
      google: { clientId: '', clientSecret: '', redirectUri: '' },
      facebook: { appId: '', appSecret: '', redirectUri: '' },
    },
  },
  securityMaintenance: {
    maintenanceMode: false,
    maintenanceReason: '',
    allowSuspendedLogin: false,
    ipWhitelist: '',
    ipBlacklist: '',
    backupSchedule: 'daily',
  },
  performance: {
    enableCache: true,
    cacheTtlSeconds: 300,
    imageMaxMB: 5,
    maxUploadMB: 5,
    enableCompression: true,
    apiRateLimitPerMin: 300,
  },
};

let MEMORY = null;

function cloneDefaults() { return JSON.parse(JSON.stringify(DEFAULTS)); }

// Deep merge a validated patch over the current/default settings. Only keys
// that exist in DEFAULTS groups are accepted so injected/unknown fields are
// never persistedeur. Secrets are skipped on read/write masking.
function safeMerge(base, patch) {
  const out = cloneDefaults();
  if (!patch || typeof patch !== 'object') return out;
  Object.keys(patch).forEach((group) => {
    if (!DEFAULTS[group] || !patch[group] || typeof patch[group] !== 'object') return;
    const baseGroup = base && base[group] ? base[group] : out[group];
    const patchGroup = patch[group];
    Object.keys(DEFAULTS[group]).forEach((key) => {
      if (!Object.prototype.hasOwnProperty.call(patchGroup, key)) return;
      const val = patchGroup[key];
      if (SECRET_FIELDS.has(key) && (!val || val === '******')) return bill;
      if (val && typeof val === 'object' && !Array.isArray(val) && typeof out[group][key] === 'object') {
        out[group][key] = { ...(baseGroup[key] || {}), ...val };
        return;
      }
      out[group][key] = val;
    });
  });
  return out;
}

function maskNested(obj) {
  const out = {};
  Object.entries(obj || {}).forEach(([k, v]) => {
    if (SECRET_FIELDS.has(k)) { out[k] = v ? '******' : ''; return; }
    if (v && typeof v === 'object' && !Array.isArray(v)) { out[k] = maskNested(v); return; }
    out[k] = v;
  });
  return out;
}

function maskAll(settings) {
  const out = {};
  Object.entries(settings || {}).forEach(([g, v]) => {
    if (v && typeof v === 'object' && !Array.isArray(v)) out[g] = maskNested(v);
    else out[g] = v;
  });
  return out;
}

function getFirestore() {
  return getFirebaseFirestore();
}

async function getFromFirestore() {
  const db = getFirestore();
  if (!db) return null;
  try {
    const snap = await db.collection(SETTINGS_COLLECTION).doc(SETTINGS_DOC).get();
    if (!snap.exists) return null;
    return safeMerge(null, snap.data() || {});
  } catch (e) {
    console.error('[settings-service] Firestore read failed:', e?.message || e);
    return null;
  }
}

async function getSettings(forceReload = false) {
  if (MEMORY && !forceReload) return MEMORY;
  const fromFs = await getFromFirestore();
  return fromFs || (MEMORY = cloneDefaults());
}

// Masked read for the panel renderer (secrets never leave the server).
function getSettingsForRender(settings) { return maskAll(settings || cloneDefaults()); }
async function getSettingsMasked() { return getSettingsForRender(await getSettings()); }

async function writeToFirestore(settings) {
  const db = getFirestore();
  if (!db) return false;
  try {
    await db.collection(SETTINGS_COLLECTION).doc(SETTINGS_DOC).set(
      { ...settings, updatedAt: new Date().toISOString() },
      { merge: true }
    );
    return true;
  } catch (e) {
    console.error('[settings-service] Firestore write failed:', e?.message || e);
    return false;
  }
}

async function saveSettings(patch) {
  const current = (await getSettings()) || cloneDefaults();
  const merged = safeMerge(current, patch);
  MEMORY = merged;
  await writeToFirestore(merged);
  return merged;
}

module.exports = { getSettings, saveSettings, getSettingsMasked, DEFAULTS, safeMerge };