const { PrismaClient } = require('@prisma/client');
const config = require('./index');

let prisma = null;

function getPrisma() {
  if (!prisma) {
    // Cap the Prisma pool explicitly. Without this, Prisma uses num_cpus*2+1
    // connections/instance — multiplied across N web instances that exhausts
    // Postgres (default max_connections=100). Append connection_limit to the
    // URL query so the engine honours it; scale by raising instance count.
    const poolLimit = parseInt(process.env.DATABASE_POOL_LIMIT) || 10;
    const url = new URL(config.database.url);
    if (!url.searchParams.has('connection_limit')) {
      url.searchParams.set('connection_limit', String(poolLimit));
    }
    prisma = new PrismaClient({
      log: config.nodeEnv === 'development' ? ['query', 'error', 'warn'] : ['error'],
      errorFormat: 'minimal',
      datasources: { db: { url: url.toString() } },
    });
  }
  return prisma;
}

async function connectDatabase() {
  try {
    const client = getPrisma();
    await client.$connect();
    console.log('[DB] PostgreSQL connected');
    return client;
  } catch (error) {
    console.error('[DB] Connection failed:', error.message);
    throw error;
  }
}

async function disconnectDatabase() {
  if (prisma) {
    await prisma.$disconnect();
    console.log('[DB] PostgreSQL disconnected');
  }
}

module.exports = { getPrisma, connectDatabase, disconnectDatabase };
