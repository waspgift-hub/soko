const { PrismaClient } = require('@prisma/client');
const logger = require('../shared/logger');

// ---------------------------------------------------------------------------
// Prisma Client Singleton
//
// WHY A SINGLETON?
// Prisma creates a connection pool on instantiation. Creating multiple
// PrismaClient instances = multiple connection pools = connection exhaustion.
// In a worker processing multiple jobs concurrently, you MUST share one
// client instance across all job handlers.
//
// CONNECTION POOL SIZING:
// Prisma default pool size is CPU_COUNT * 2 + 1. On Render's free tier
// (512 MB RAM, 1 CPU), that's 3 connections. On paid plans (2+ CPU),
// increase via ?connection_limit=10 in DATABASE_URL.
// ---------------------------------------------------------------------------

let prisma = null;

function getPrisma() {
  if (!prisma) {
    prisma = new PrismaClient({
      log: [
        { level: 'error', emit: 'event' },
        { level: 'warn', emit: 'event' },
      ],
    });

    prisma.$on('error', (e) => {
      logger.error({ prismaEvent: e }, 'Prisma error event');
    });
  }
  return prisma;
}

async function closePrisma() {
  if (prisma) {
    await prisma.$disconnect();
    prisma = null;
  }
}

module.exports = { getPrisma, closePrisma };
