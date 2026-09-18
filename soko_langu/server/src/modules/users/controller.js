const { getPrisma } = require('../../config/database');
const { SettingsStateMachine, SETTINGS_DOMAINS } = require('./settings-state-machine');
const { ACCOUNT_STATES } = require('./account-state-machine');

// Get all settings for current user
async function getSettings(req, res) {
  try {
    const prisma = getPrisma();
    
    const settings = await prisma.userSetting.findMany({
      where: { userId: req.user.id },
    });

    const result = {};
    for (const s of settings) {
      result[s.domain] = s.settings;
    }

    // Fill in defaults for missing domains
    for (const domain of SETTINGS_DOMAINS) {
      if (!result[domain]) {
        result[domain] = getDefaultSettings(domain);
      }
    }

    res.json(result);
  } catch (error) {
    console.error('[SETTINGS] Get error:', error.message);
    res.status(500).json({ error: 'Failed to load settings' });
  }
}

// Update settings for a specific domain
async function updateSettings(req, res) {
  try {
    const { domain } = req.params;
    
    if (!SETTINGS_DOMAINS.includes(domain)) {
      return res.status(400).json({ error: `Invalid settings domain: ${domain}` });
    }

    const changes = req.body.settings || req.body;
    
    // Validate against domain rules
    const machine = new SettingsStateMachine(domain);
    const validation = machine.validate(changes);
    
    if (!validation.valid) {
      return res.status(400).json({
        error: 'VALIDATION_FAILED',
        details: validation.invalidFields,
      });
    }

    machine.transition('load_server');
    
    const prisma = getPrisma();
    
    // Check if settings exist
    const existing = await prisma.userSetting.findUnique({
      where: {
        userId_domain: {
          userId: req.user.id,
          domain,
        },
      },
    });

    machine.transition('user_edits');
    machine.transition('client_validate');
    machine.transition('authenticated_write');
    
    // Only active users can update settings
    if (req.user.accountStatus === ACCOUNT_STATES.DELETION_PENDING) {
      return res.status(403).json({ error: 'ACCOUNT_DELETION_PENDING' });
    }

    machine.transition('server_authorization');

    let updated;
    if (existing) {
      updated = await prisma.userSetting.update({
        where: { id: existing.id },
        data: {
          settings: changes,
          version: { increment: 1 },
        },
      });
    } else {
      updated = await prisma.userSetting.create({
        data: {
          userId: req.user.id,
          domain,
          settings: changes,
        },
      });
    }

    machine.transition('db_transaction');
    machine.transition('audit');
    machine.transition('cache_refresh');
    machine.transition('updated');

    res.json({
      success: true,
      domain,
      settings: updated.settings,
      version: updated.version,
    });
  } catch (error) {
    console.error('[SETTINGS] Update error:', error.message);
    res.status(500).json({ error: 'Failed to update settings' });
  }
}

// Request account deletion
async function requestDeletion(req, res) {
  try {
    const prisma = getPrisma();
    
    // Set account to deletion pending
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: {
        accountStatus: ACCOUNT_STATES.DELETION_PENDING,
      },
    });

    // Create audit log
    await prisma.auditLog.create({
      data: {
        actorId: user.id,
        actorType: 'user',
        action: 'REQUEST_ACCOUNT_DELETION',
        entityType: 'user',
        entityId: user.id,
        newState: { accountStatus: ACCOUNT_STATES.DELETION_PENDING },
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'],
      },
    });

    res.json({
      success: true,
      message: 'Account deletion requested. You have 30 days to cancel.',
      gracePeriodDays: 30,
    });
  } catch (error) {
    console.error('[SETTINGS] Deletion error:', error.message);
    res.status(500).json({ error: 'Failed to request deletion' });
  }
}

// Export user data
async function exportData(req, res) {
  try {
    const prisma = getPrisma();
    
    const [user, settings, addresses] = await Promise.all([
      prisma.user.findUnique({ where: { id: req.user.id } }),
      prisma.userSetting.findMany({ where: { userId: req.user.id } }),
      prisma.address.findMany({ where: { userId: req.user.id } }),
    ]);

    res.json({
      success: true,
      data: {
        profile: {
          displayName: user.displayName,
          email: user.email,
          phone: user.phone,
          createdAt: user.createdAt,
        },
        settings,
        addresses,
      },
    });
  } catch (error) {
    console.error('[SETTINGS] Export error:', error.message);
    res.status(500).json({ error: 'Failed to export data' });
  }
}

function getDefaultSettings(domain) {
  const defaults = {
    profile: {},
    security: { twoFactorEnabled: false },
    privacy: { showEmail: false, showPhone: false, profileVisibility: 'public' },
    notifications: { pushEnabled: true, emailEnabled: true, smsEnabled: false },
    shopping: {},
    selling: {},
    payments: {},
    language_region: { preferredLanguage: 'sw', preferredCurrency: 'TZS' },
    accessibility: { fontScale: 1.0, highContrast: false, reduceMotion: false },
    data_deletion: {},
  };
  return defaults[domain] || {};
}

// Extended profile fields the app stores in Firestore users/{uid} that have no
// dedicated Postgres column. Kept under metadata.profile so reads are a single
// document fetch and no schema migration is needed (Phase D bridge).
const PROFILE_META_FIELDS = [
  'location', 'mood', 'latitude', 'longitude', 'paymentNumbers',
  'shopBanner', 'shopBannerColor', 'shopAccentColor', 'gender', 'dateOfBirth',
];

// Columns that map 1:1 from the client profile payload.
const PROFILE_COLUMN_FIELDS = {
  displayName: 'displayName',
  username: 'username',
  bio: 'bio',
  phone: 'phone',
  email: 'email',
  profileImage: 'avatarUrl',
  langCode: 'preferredLanguage',
};

// Shape the app's UserProfile.fromMap reads from Firestore users/{uid}; key
// names match so the Dart side can keep its existing model.
function serializeSelfProfile(user, kycApproved, lastActive) {
  const meta = user.metadata && typeof user.metadata === 'object' ? user.metadata : {};
  const p = meta.profile || {};
  return {
    id: user.firebaseUid,
    displayName: user.displayName || '',
    username: user.username || '',
    bio: user.bio || '',
    phone: user.phone || '',
    email: user.email || '',
    location: p.location || '',
    mood: p.mood || '',
    latitude: p.latitude ?? null,
    longitude: p.longitude ?? null,
    profileImage: user.avatarUrl || '',
    paymentNumbers: p.paymentNumbers || {},
    shopBanner: p.shopBanner || '',
    shopBannerColor: p.shopBannerColor || '',
    shopAccentColor: p.shopAccentColor || '',
    kyc: { approved: Boolean(kycApproved) },
    gender: p.gender || '',
    dateOfBirth: p.dateOfBirth || '',
    lastActive: lastActive ? lastActive.toISOString() : null,
    langCode: user.preferredLanguage || 'sw',
    createdAt: user.createdAt ? user.createdAt.toISOString() : null,
    updatedAt: user.updatedAt ? user.updatedAt.toISOString() : null,
  };
}

// Splits a client profile payload into column data + metadata.profile fields.
// Extra keys are dropped; the result is the safe whitelisted shape for PUT /me.
function applyProfileUpdate(user, body) {
  const data = body && typeof body === 'object' ? body : {};
  const col = {};
  const metaFields = {};
  for (const [clientKey, dbKey] of Object.entries(PROFILE_COLUMN_FIELDS)) {
    if (clientKey in data) {
      const v = data[clientKey];
      col[dbKey] = (typeof v === 'string' && v.trim() === '') ? null : v;
    }
  }
  for (const f of PROFILE_META_FIELDS) {
    if (f in data) metaFields[f] = data[f];
  }
  const currentMeta = user.metadata && typeof user.metadata === 'object' ? user.metadata : {};
  const mergedProfile = { ...(currentMeta.profile || {}), ...metaFields };
  const meta = { ...currentMeta, profile: mergedProfile };
  return { col, meta };
}

// GET /api/v1/users/me — the current user's profile in Firestore users/{uid}
// shape. Self profile + KYC flag; used as the primary read for the app profile.
async function getMe(req, res) {
  try {
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });

    const kyc = await prisma.kycApplication.findUnique({
      where: { userId: user.firebaseUid },
      select: { status: true, approved: true },
    });
    const lastActiveRaw = user.metadata && user.metadata.lastActive
      ? new Date(user.metadata.lastActive)
      : null;

    res.json({
      success: true,
      data: serializeSelfProfile(
        user,
        kyc && kyc.approved && kyc.status === 'approved',
        lastActiveRaw,
      ),
    });
  } catch (error) {
    console.error('[USERS] Get /me error:', error.message);
    res.status(500).json({ error: 'Failed to load profile' });
  }
}

// PUT /api/v1/users/me — storefront/profile edits. Whitelisted fields are
// persisted to Postgres columns or metadata.profile; unknown fields are ignored.
async function updateMe(req, res) {
  try {
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id: req.user.id } });
    if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });

    const { col, meta } = applyProfileUpdate(user, req.body);

    const updated = await prisma.user.update({
      where: { id: req.user.id },
      data: { ...col, metadata: meta },
    });

    const kyc = await prisma.kycApplication.findUnique({
      where: { userId: user.firebaseUid },
      select: { status: true, approved: true },
    });

    res.json({
      success: true,
      data: serializeSelfProfile(
        updated,
        kyc && kyc.approved && kyc.status === 'approved',
        meta.lastActive ? new Date(meta.lastActive) : null,
      ),
    });
  } catch (error) {
    console.error('[USERS] PUT /me error:', error.message);
    res.status(500).json({ error: 'Failed to update profile' });
  }
}

// GET /api/v1/users/public/:identifier — a public profile for another user
// (buyer or seller) by Firebase UID or Postgres uuid. No private fields; used
// by chat and review flows that previously read Firestore users/{uid}.
async function getPublicProfile(req, res) {
  try {
    const { identifier } = req.params;
    if (!identifier) return res.status(400).json({ error: 'MISSING_IDENTIFIER' });

    const prisma = getPrisma();
    const user = await prisma.user.findFirst({
      where: {
        OR: [
          { firebaseUid: identifier },
          { id: identifier },
        ],
      },
      include: { sellerProfile: true },
    });
    if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });

    const meta = user.metadata && typeof user.metadata === 'object' ? user.metadata : {};
    const p = meta.profile || {};

    res.json({
      success: true,
      data: {
        id: user.firebaseUid,
        displayName: user.displayName || '',
        username: user.username || '',
        bio: user.bio || '',
        location: p.location || '',
        mood: p.mood || '',
        profileImage: user.avatarUrl || '',
        lastActive: meta.lastActive ? new Date(meta.lastActive).toISOString() : null,
        role: user.role,
        isSeller: Boolean(user.sellerProfile && user.sellerProfile.sellerStatus === 'seller'),
        seller: user.sellerProfile
          ? {
              storeName: user.sellerProfile.storeName,
              storeSlug: user.sellerProfile.storeSlug,
              logoUrl: user.sellerProfile.logoUrl || '',
              coverUrl: user.sellerProfile.coverUrl || '',
              verificationStatus: user.sellerProfile.verificationStatus,
            }
          : null,
      },
    });
  } catch (error) {
    console.error('[USERS] public profile error:', error.message);
    res.status(500).json({ error: 'Failed to load profile' });
  }
}

module.exports = {
  getSettings,
  updateSettings,
  requestDeletion,
  exportData,
  serializeSelfProfile,
  applyProfileUpdate,
  getMe,
  updateMe,
  getPublicProfile,
};
