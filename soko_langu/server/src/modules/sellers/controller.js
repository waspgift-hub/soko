const { getPrisma } = require('../../config/database');
const { SellerStateMachine, SELLER_STATES } = require('./seller-state-machine');

// Request to become a seller
async function requestSellerMode(req, res) {
  try {
    const prisma = getPrisma();
    
    // Check current seller state
    const existing = await prisma.sellerProfile.findUnique({
      where: { userId: req.user.id },
    });

    const machine = new SellerStateMachine(existing?.sellerStatus || SELLER_STATES.NOT_SELLER);

    // Can only request if not already a seller
    if (machine.currentState === SELLER_STATES.ACTIVE) {
      return res.status(400).json({ error: 'Already a seller' });
    }

    if (existing) {
      await prisma.sellerProfile.update({
        where: { id: existing.id },
        data: { sellerStatus: SELLER_STATES.MODE_REQUESTED },
      });
    } else {
      await prisma.sellerProfile.create({
        data: {
          userId: req.user.id,
          storeName: '',  // Must be filled in profile step
          storeSlug: '',  // Must be filled in profile step
          sellerStatus: SELLER_STATES.MODE_REQUESTED,
        },
      });
    }

    // Update user role
    await prisma.user.update({
      where: { id: req.user.id },
      data: { role: 'seller' },
    });

    res.json({
      success: true,
      nextStep: 'PROFILE_REQUIRED',
      message: 'Seller mode requested. Complete your store profile to continue.',
    });
  } catch (error) {
    console.error('[SELLER] Request error:', error.message);
    res.status(500).json({ error: 'Failed to request seller mode' });
  }
}

// Create seller profile
async function createSellerProfile(req, res) {
  try {
    const { storeName, storeDescription, businessType } = req.body;
    
    if (!storeName || !storeName.trim()) {
      return res.status(400).json({ error: 'Store name is required' });
    }

    const prisma = getPrisma();
    
    const existing = await prisma.sellerProfile.findUnique({
      where: { userId: req.user.id },
    });

    // Generate unique slug
    const slug = storeName
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '')
      .slice(0, 50);

    const machine = new SellerStateMachine(existing?.sellerStatus || SELLER_STATES.NOT_SELLER);

    let profile;
    if (existing) {
      profile = await prisma.sellerProfile.update({
        where: { id: existing.id },
        data: {
          storeName: storeName.trim(),
          storeSlug: slug + '-' + req.user.id.slice(0, 8),
          storeDescription,
          businessType,
          sellerStatus: SELLER_STATES.ELIGIBILITY_CHECK,
        },
      });
    } else {
      profile = await prisma.sellerProfile.create({
        data: {
          userId: req.user.id,
          storeName: storeName.trim(),
          storeSlug: slug + '-' + req.user.id.slice(0, 8),
          storeDescription,
          businessType,
          sellerStatus: SELLER_STATES.ELIGIBILITY_CHECK,
        },
      });
    }

    // Run eligibility check
    const eligibility = SellerStateMachine.checkEligibility({
      ...profile,
      accountStatus: req.user.accountStatus === 'active' ? 'active' : 'inactive',
      kycRequired: false, // Simplified - would be real KYC system
    });

    let newStatus;
    if (eligibility.pass) {
      newStatus = SELLER_STATES.ACTIVE;
    } else {
      newStatus = SELLER_STATES.PENDING_REVIEW;
    }

    profile = await prisma.sellerProfile.update({
      where: { id: profile.id },
      data: { sellerStatus: newStatus },
    });

    // Create wallet for seller
    const existingWallet = await prisma.wallet.findUnique({
      where: { sellerId: profile.id },
    });

    if (!existingWallet) {
      await prisma.wallet.create({
        data: {
          sellerId: profile.id,
        },
      });
    }

    res.json({
      success: true,
      sellerStatus: newStatus,
      eligibility,
      message: newStatus === SELLER_STATES.ACTIVE 
        ? 'Your store is now active!' 
        : 'Your profile needs manual review. We will notify you.',
    });
  } catch (error) {
    console.error('[SELLER] Create error:', error.message);
    res.status(500).json({ error: 'Failed to create seller profile' });
  }
}

// Get own seller profile
async function getSellerProfile(req, res) {
  try {
    const prisma = getPrisma();
    
    const profile = await prisma.sellerProfile.findUnique({
      where: { userId: req.user.id },
      include: {
        products: {
          where: { deletedAt: null },
          select: {
            id: true,
            title: true,
            price: true,
            status: true,
            stock: true,
          },
        },
        wallets: true,
      },
    });

    if (!profile) {
      return res.status(404).json({ error: 'Seller profile not found' });
    }

    res.json(profile);
  } catch (error) {
    console.error('[SELLER] Get error:', error.message);
    res.status(500).json({ error: 'Failed to load seller profile' });
  }
}

// Update seller profile
async function updateSellerProfile(req, res) {
  try {
    const { storeName, storeDescription, logoUrl, coverUrl, businessType } = req.body;
    
    const prisma = getPrisma();
    
    const profile = await prisma.sellerProfile.update({
      where: { userId: req.user.id },
      data: {
        storeName: storeName?.trim(),
        storeDescription,
        logoUrl,
        coverUrl,
        businessType,
      },
    });

    res.json({ success: true, profile });
  } catch (error) {
    console.error('[SELLER] Update error:', error.message);
    res.status(500).json({ error: 'Failed to update seller profile' });
  }
}

// Get seller dashboard
async function getSellerDashboard(req, res) {
  try {
    const prisma = getPrisma();
    
    const profile = await prisma.sellerProfile.findUnique({
      where: { userId: req.user.id },
    });

    if (!profile) {
      return res.status(404).json({ error: 'Seller profile not found' });
    }

    const [orders, recentOrders, wallet] = await Promise.all([
      prisma.order.count({ where: { sellerId: profile.id } }),
      prisma.order.findMany({
        where: { sellerId: profile.id },
        orderBy: { createdAt: 'desc' },
        take: 10,
        select: {
          id: true,
          orderNumber: true,
          status: true,
          totalAmount: true,
          createdAt: true,
        },
      }),
      prisma.wallet.findUnique({ where: { sellerId: profile.id } }),
    ]);

    res.json({
      stats: {
        totalOrders: orders,
        totalRevenue: wallet?.totalEarned || 0,
        availableBalance: wallet?.availableBalance || 0,
        pendingBalance: wallet?.pendingBalance || 0,
        reliabilityScore: profile.reliabilityScore,
      },
      recentOrders,
    });
  } catch (error) {
    console.error('[SELLER] Dashboard error:', error.message);
    res.status(500).json({ error: 'Failed to load dashboard' });
  }
}

module.exports = {
  requestSellerMode,
  createSellerProfile,
  getSellerProfile,
  updateSellerProfile,
  getSellerDashboard,
};
