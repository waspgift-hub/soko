const { PrismaClient } = require('@prisma/client');
const config = require('./index');

let prisma = null;

function getPrisma() {
  if (!prisma) {
    prisma = new PrismaClient({
      log: config.nodeEnv === 'development' ? ['query', 'error', 'warn'] : ['error'],
      errorFormat: 'minimal',
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
