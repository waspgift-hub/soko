const { getStore } = require('../../config/database');
const { SettingsStateMachine, SETTINGS_DOMAINS } = require('./settings-state-machine');
const { ACCOUNT_STATES } = require('./account-state-machine');
const accountStore = require('../../services/account-store');

// Get all settings for current user
async function getSettings(req, res) {
  try {
    const store = getStore();
    
    const settings = await store.userSetting.findMany({
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
    
    const store = getStore();
    
    // Check if settings exist
    const existing = await store.userSetting.findUnique({
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
      updated = await store.userSetting.update({
        where: { id: existing.id },
        data: {
          settings: changes,
          version: { increment: 1 },
        },
      });
    } else {
      updated = await store.userSetting.create({
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

// Request account deletion. The flag lives on the Firestore users/{uid} doc
// (mirrored to Postgres) so every read path honours the 30-day grace period.
async function requestDeletion(req, res) {
  try {
    const store = getStore();

    if (req.user.accountStatus !== ACCOUNT_STATES.DELETION_PENDING) {
      await accountStore.updateFlags(req.firebaseUid, { accountStatus: ACCOUNT_STATES.DELETION_PENDING });
    }

    // Create audit log
    await store.auditLog.create({
      data: {
        actorId: req.user.id,
        actorType: 'user',
        action: 'REQUEST_ACCOUNT_DELETION',
        entityType: 'user',
        entityId: req.user.id,
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

// Export user data — Firestore profile is authoritative; Postgres rows supply
// the settings and addresses the app has not yet mirrored.
async function exportData(req, res) {
  try {
    const store = getStore();
    const fsProfile = await accountStore.getProfile(req.firebaseUid);

    const [user, settings, addresses] = await Promise.all([
      store.user.findUnique({ where: { id: req.user.id } }),
      store.userSetting.findMany({ where: { userId: req.user.id } }),
      store.address.findMany({ where: { userId: req.user.id } }),
    ]);

    const profile = fsProfile
      ? {
          displayName: fsProfile.displayName || null,
          email: fsProfile.email || null,
          phone: fsProfile.phone || null,
          createdAt: fsProfile.createdAt || null,
        }
      : {
          displayName: user.displayName || null,
          email: user.email || null,
          phone: user.phone || null,
          createdAt: user.createdAt ? user.createdAt.toISOString() : null,
        };

    res.json({
      success: true,
      data: { profile, settings, addresses },
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

// Shape the app's UserProfile.fromMap reads from Firestore users/{uid}; key
// names match so the Dart side can keep its existing model. Only used in the
// legacy Postgres fallback path (accounts that have no Firestore doc yet).
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

// GET /api/v1/users/me — the current user's profile, Firestore-primary.
// Firestore users/{uid} is the authoritative app profile; Postgres is only a
// legacy fallback for accounts created before the account-store existed.
async function getMe(req, res) {
  try {
    const uid = req.firebaseUid;
    const doc = await accountStore.getProfile(uid);
    if (doc) {
      return res.json({ success: true, data: accountStore.serializeFirestoreProfile(doc) });
    }

    const store = getStore();
    const user = await store.user.findUnique({ where: { id: req.user.id } });
    if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });

    const kyc = await store.kycApplication.findUnique({
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

// PUT /api/v1/users/me — storefront/profile edits land in Firestore first;
// the seam row is then written so money-facing modules keep their uuid join.
async function updateMe(req, res) {
  try {
    const uid = req.firebaseUid;
    const doc = await accountStore.getProfile(uid);
    const current = doc || { metadata: {} };
    const { col, meta } = accountStore.applyProfileUpdate(current, req.body);

    await accountStore.writeProfile(uid, { col, meta });

    const fresh = (await accountStore.getProfile(uid)) || {
      ...current,
      ...col,
      metadata: meta,
      userId: uid,
    };
    res.json({ success: true, data: accountStore.serializeFirestoreProfile(fresh) });
  } catch (error) {
    console.error('[USERS] PUT /me error:', error.message);
    res.status(500).json({ error: 'Failed to update profile' });
  }
}

// GET /api/v1/users/public/:identifier — a public profile for another user
// (buyer or seller) by Firebase UID or Profile User id. Firestore-primary;
// legacy accounts fall back to Postgres for seller-profile details.
async function getPublicProfile(req, res) {
  try {
    const { identifier } = req.params;
    if (!identifier) return res.status(400).json({ error: 'MISSING_IDENTIFIER' });

    const doc = await accountStore.getProfile(identifier);
    if (doc) {
      const s = accountStore.serializeFirestoreProfile({ ...doc, userId: identifier });
      return res.json({
        success: true,
        data: {
          id: identifier,
          displayName: s.displayName,
          username: s.username,
          bio: s.bio,
          location: s.location,
          mood: s.mood,
          profileImage: s.profileImage,
          lastActive: s.lastActive,
          role: doc.role || 'buyer',
          isSeller: Boolean(doc.sellerProfile && doc.sellerProfile.sellerStatus === 'seller'),
          seller: doc.sellerProfile
            ? {
                storeName: doc.sellerProfile.storeName,
                storeSlug: doc.sellerProfile.storeSlug,
                logoUrl: doc.sellerProfile.logoUrl || '',
                coverUrl: doc.sellerProfile.coverUrl || '',
                verificationStatus: doc.sellerProfile.verificationStatus,
              }
            : null,
        },
      });
    }

    // uuid columns reject non-uuid comparison values, so only add the id arm
    // when the identifier actually looks like a Postgres uuid.
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(identifier);
    const store = getStore();
    const user = await store.user.findFirst({
      where: isUuid
        ? { OR: [{ firebaseUid: identifier }, { id: identifier }] }
        : { firebaseUid: identifier },
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

// GET /api/v1/users/check-username?username=X&excludeUid=Y — username
// uniqueness check behind the profile edit flow. Firestore query first;
// Postgres fallback covers legacy rows. excludeUid may be a Firebase UID or
// Postgres uuid; the owner's own username never counts as taken.
async function checkUsername(req, res) {
  try {
    const q = String(req.query.username || '').trim();
    if (!q) return res.status(400).json({ error: 'MISSING_USERNAME' });
    const excludeUid = String(req.query.excludeUid || '');
    const norm = q.toLowerCase();

    const fs = await accountStore.byUsernameFirestore(norm);
    let foundId = fs ? fs._uid : null;

    if (!foundId) {
      const store = getStore();
      const row = await store.user.findFirst({
        where: { username: norm },
        select: { id: true, firebaseUid: true },
      });
      if (row) foundId = row.firebaseUid || row.id;
    }

    let available = !foundId;
    if (foundId && excludeUid) {
      if (foundId === excludeUid) available = true;
    }

    res.json({ success: true, data: { available, username: foundId ? norm : q } });
  } catch (error) {
    console.error('[USERS] check-username error:', error.message);
    res.status(500).json({ error: 'Failed to check username' });
  }
}

module.exports = {
  getSettings,
  updateSettings,
  requestDeletion,
  exportData,
  serializeSelfProfile,
  getMe,
  updateMe,
  getPublicProfile,
  checkUsername,
};
