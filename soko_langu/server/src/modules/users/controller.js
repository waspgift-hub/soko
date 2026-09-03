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

module.exports = {
  getSettings,
  updateSettings,
  requestDeletion,
  exportData,
};
