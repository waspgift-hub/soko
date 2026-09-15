const { PrismaClient } = require('@prisma/client');
const config = require('./index');

let prisma = null;

// Build a PrismaClient bound to `url` with a fixed pool cap. The cap exists
// because Prisma otherwise opens num_cpus*2+1 connections per instance and
// N web instances × open sockets exhausts Postgres (max_connections=100).
function buildClient(url) {
  const poolLimit = parseInt(process.env.DATABASE_POOL_LIMIT) || 10;
  const u = new URL(url);
  if (!u.searchParams.has('connection_limit')) {
    u.searchParams.set('connection_limit', String(poolLimit));
  }
  let client;
  try {
    client = new PrismaClient({
      log: config.nodeEnv === 'development' ? ['query', 'error', 'warn'] : ['error'],
      errorFormat: 'minimal',
      datasources: { db: { url: u.toString() } },
    });
  } catch (e) {
    console.error('[DB] PrismaClient init failed:', e.message);
    throw e;
  }
  return client;
}

// Read replica: when DATABASE_URL_REPLICA is set, hot catalog reads route here
// (products/categories) while every write stays on the primary. No replica yet
// => readonly falls back to the same instance (behaviour unchanged).
let readPrisma = null;

function getReadPrisma() {
  if (!config.database.replicaUrl) return getPrisma();
  if (!readPrisma) {
    readPrisma = buildClient(config.database.replicaUrl);
  }
  return readPrisma;
}

function getPrisma() {
  if (!prisma) {
    prisma = buildClient(config.database.url);
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
  if (readPrisma && readPrisma !== prisma) {
    await readPrisma.$disconnect();
    console.log('[DB] PostgreSQL replica disconnected');
  }
}

module.exports = { getPrisma, getReadPrisma, connectDatabase, disconnectDatabase };
