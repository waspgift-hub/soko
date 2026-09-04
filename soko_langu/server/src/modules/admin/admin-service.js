const { getPrisma } = require('../../config/database');

/**
 * Admin dashboard KPIs: revenue, orders, users, disputes, system health.
 */
async function getDashboard() {
  const prisma = getPrisma();
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const [users, newUsers, orders, completedOrders, revenue, activeDisputes, escrowHeld, products] =
    await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { createdAt: { gte: today } } }),
      prisma.order.count(),
      prisma.order.count({ where: { status: { in: ['completed', 'wallet_credited', 'payout_pending', 'payout_complete'] } } }),
      prisma.order.aggregate({
        _sum: { platformCommission: true },
        where: { status: { in: ['completed', 'wallet_credited'] } },
      }),
      prisma.dispute.count({ where: { status: 'open' } }),
      prisma.escrowHold.aggregate({
        _sum: { amount: true },
        where: { status: 'holding' },
      }),
      prisma.product.count(),
    ]);

  return {
    kpis: {
      users,
      newUsersToday: newUsers,
      orders,
      completedOrders,
      commissionRevenue: revenue._sum.platformCommission?.toString() || '0',
      activeDisputes,
      escrowHeld: escrowHeld._sum.amount?.toString() || '0',
      products,
    },
  };
}

/**
 * Search users for admin (by email, phone, username, id).
 */
async function searchUsers({ q, role, accountStatus, page = 1, limit = 20 }) {
  const prisma = getPrisma();
  const where = {
    ...(q
      ? {
          OR: [
            { email: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q } },
            { username: { contains: q, mode: 'insensitive' } },
            { displayName: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
    ...(role ? { role } : {}),
    ...(accountStatus ? { accountStatus } : {}),
  };

  const [users, total] = await Promise.all([
    prisma.user.findMany({
      where,
      select: {
        id: true,
        email: true,
        phone: true,
        username: true,
        displayName: true,
        avatarUrl: true,
        role: true,
        accountStatus: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.user.count({ where }),
  ]);

  return { users, pagination: { page: Number(page), limit: Number(limit), total } };
}

/**
 * Get all transactions/ledger for admin financial module.
 */
async function listLedger({ type, page = 1, limit = 50 }) {
  const prisma = getPrisma();
  const where = type ? { type } : {};
  const [entries, total] = await Promise.all([
    prisma.walletLedgerEntry.findMany({
      where,
      include: { wallet: { include: { seller: true } } },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.walletLedgerEntry.count({ where }),
  ]);
  return { entries, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function listAuditLogs({ action, entityType, actorId, page = 1, limit = 50 }) {
  const prisma = getPrisma();
  const where = {};
  if (action) where.action = action;
  if (entityType) where.entityType = entityType;
  if (actorId) where.actorId = actorId;
  const [entries, total] = await Promise.all([
    prisma.auditLog.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    prisma.auditLog.count({ where }),
  ]);
  return { entries, pagination: { page: Number(page), limit: Number(limit), total } };
}

async function getMetrics() {
  const prisma = getPrisma();
  const [
    userCount,
    orderStatusGroups,
    paymentStatusGroups,
    withdrawalsPending,
    disputesOpen,
    escrowHolding,
  ] = await Promise.all([
    prisma.user.count(),
    prisma.order.groupBy({ by: ['status'], _count: { status: true }, _sum: { totalAmount: true } }),
    prisma.payment.groupBy({ by: ['status'], _count: { status: true }, _sum: { amount: true } }),
    prisma.withdrawal.count({ where: { status: { in: ['pending', 'processing'] } } }),
    prisma.dispute.count({ where: { status: { in: ['open', 'under_review'] } } }),
    prisma.escrowHold.aggregate({ _sum: { amount: true }, _count: true }),
  ]);
  const gmv = orderStatusGroups
    .filter((g) => !['cancelled', 'refunded'].includes(g.status))
    .reduce((sum, g) => sum + Number(g._sum.totalAmount || 0), 0);
  return {
    users: userCount,
    gmv,
    ordersByStatus: orderStatusGroups.map((g) => ({
      status: g.status,
      count: g._count.status,
      totalAmount: Number(g._sum.totalAmount || 0).toString(),
    })),
    paymentsByStatus: paymentStatusGroups.map((g) => ({
      status: g.status,
      count: g._count.status,
      totalAmount: Number(g._sum.amount || 0).toString(),
    })),
    withdrawalsPending,
    disputesOpen,
    escrowHolding: {
      count: escrowHolding._count,
      totalAmount: Number(escrowHolding._sum.amount || 0).toString(),
    },
  };
}

module.exports = { getDashboard, searchUsers, listLedger, listAuditLogs, getMetrics };
