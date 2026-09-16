const { getPrisma } = require('../../config/database');

const PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

async function listNotifications(userId, { page = 1, limit = PAGE_SIZE } = {}) {
  const prisma = getPrisma();
  const take = Math.min(Math.max(1, limit), MAX_PAGE_SIZE);
  const skip = (Math.max(1, page) - 1) * take;

  const [items, total] = await Promise.all([
    prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      skip,
      take,
    }),
    prisma.notification.count({ where: { userId } }),
  ]);

  return {
    notifications: items.map(n => ({
      id: n.id,
      userId: n.userId,
      type: n.type,
      title: n.title,
      body: n.body,
      data: n.data,
      isRead: n.readAt != null,
      createdAt: n.createdAt.toISOString(),
    })),
    pagination: { page, limit: take, total, totalPages: Math.ceil(total / take) },
  };
}

async function unreadCount(userId) {
  const prisma = getPrisma();
  return prisma.notification.count({
    where: { userId, readAt: null },
  });
}

async function markRead(userId, notificationId) {
  const prisma = getPrisma();
  const updated = await prisma.notification.updateMany({
    where: { id: notificationId, userId, readAt: null },
    data: { readAt: new Date() },
  });
  return updated.count > 0;
}

async function markAllRead(userId) {
  const prisma = getPrisma();
  const updated = await prisma.notification.updateMany({
    where: { userId, readAt: null },
    data: { readAt: new Date() },
  });
  return updated.count;
}

async function deleteNotification(userId, notificationId) {
  const prisma = getPrisma();
  const deleted = await prisma.notification.deleteMany({
    where: { id: notificationId, userId },
  });
  return deleted.count > 0;
}

async function deleteAll(userId) {
  const prisma = getPrisma();
  const deleted = await prisma.notification.deleteMany({
    where: { userId },
  });
  return deleted.count;
}

module.exports = {
  listNotifications,
  unreadCount,
  markRead,
  markAllRead,
  deleteNotification,
  deleteAll,
};
