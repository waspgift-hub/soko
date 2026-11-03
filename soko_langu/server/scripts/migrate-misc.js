// Phase D backfill: mirror Firestore `reviews`, `users/{uid}.kyc`, and
// `notifications` into Postgres so the v1 flag-gated bridges lose nothing.
// Dry-run by default; pass --commit to write. Idempotent: skips rows that
// already exist in Postgres.

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '..', '.env.production') });

const admin = require('firebase-admin');
const { PrismaClient } = require('@prisma/client');

if (!process.env.DATABASE_URL) { console.error('FATAL: DATABASE_URL not set'); process.exit(1); }
if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) { console.error('FATAL: FIREBASE_SERVICE_ACCOUNT_JSON not set'); process.exit(1); }

const COMMIT = process.argv.includes('--commit');
const prisma = new PrismaClient({ datasources: { db: { url: process.env.DATABASE_URL } } });
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)),
});
const fs = admin.firestore();

const toDate = (v) => {
  if (!v) return null;
  const d = v.toDate ? v.toDate() : v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
};
const num = (v, d) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : d;
};
const str = (v) => (typeof v === 'string' ? v : '');

const sellerIdCache = new Map();

async function resolveReviewSellerId(productId) {
  if (!productId) return null;
  if (sellerIdCache.has(productId)) return sellerIdCache.get(productId);
  let sellerId = null;
  try {
    const p = await fs.collection('products').doc(productId).get();
    if (p.exists) sellerId = str(p.data()?.sellerId) || null;
  } catch (_) { /* best effort */ }
  sellerIdCache.set(productId, sellerId);
  return sellerId;
}

async function backfillReviews() {
  const snap = await fs.collection('reviews').get();
  let created = 0, skipped = 0, errored = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const userId = str(d.userId);
    const productId = str(d.productId);
    if (!userId || !productId) { skipped++; continue; }
    const exists = await prisma.review.findFirst({
      where: { userId, productId, comment: d.comment || null, createdAt: toDate(d.createdAt) || undefined },
      select: { id: true },
    });
    if (exists) { skipped++; continue; }
    let sellerId = str(d.sellerId) || null;
    if (!sellerId) sellerId = await resolveReviewSellerId(productId);
    if (!COMMIT) { created++; continue; }
    try {
      await prisma.review.create({
        data: {
          productId,
          sellerId: sellerId || '-',
          userId,
          userName: str(d.userName) || 'Anonymous',
          userImage: str(d.userImage) || null,
          rating: Math.max(1, Math.min(5, num(d.rating, 5))),
          comment: d.comment ? String(d.comment) : null,
          images: Array.isArray(d.images) ? d.images : [],
          helpfulCount: num(d.helpfulCount, 0),
          likedBy: Array.isArray(d.likedBy) ? d.likedBy : [],
          isVerifiedPurchase: d.isVerifiedPurchase === true,
          sellerReply: d.sellerReply ? String(d.sellerReply) : null,
          sellerReplyAt: toDate(d.sellerReplyAt),
          createdAt: toDate(d.createdAt) || new Date(d.createdAt?.toMillis?.() || Date.now()),
        },
      });
      created++;
    } catch (e) {
      errored++;
      console.error(`[reviews] skip ${doc.id}: ${e.message}`);
    }
  }
  console.log(`[reviews] done. total=${snap.size} created=${created} skipped=${skipped} errors=${errored}`);
}

async function backfillKyc() {
  const users = await fs.collection('users').get();
  let created = 0, errored = 0;
  for (const u of users.docs) {
    const k = u.data().kyc;
    if (!k || !k.fullName) continue;
    if (!COMMIT) { created++; continue; }
    try {
      await prisma.kycApplication.upsert({
        where: { userId: u.id },
        update: {
          fullName: str(k.fullName),
          idType: str(k.idType) || 'National ID',
          idNumber: str(k.idNumber) || '-',
          idImageUrl: str(k.idImageUrl) || null,
          selfieUrl: str(k.selfieUrl) || null,
          status: ['pending', 'approved', 'rejected', 'revoked'].includes(k.status) ? k.status : 'pending',
          approved: k.approved === true,
          reviewNotes: str(k.reviewNotes) || null,
          submittedAt: toDate(k.submittedAt) || new Date(u.updateTime?.toMillis?.() || Date.now()),
          reviewedAt: toDate(k.reviewedAt),
          revokedAt: toDate(k.revokedAt),
        },
        create: {
          userId: u.id,
          fullName: str(k.fullName),
          idType: str(k.idType) || 'National ID',
          idNumber: str(k.idNumber) || '-',
          idImageUrl: str(k.idImageUrl) || null,
          selfieUrl: str(k.selfieUrl) || null,
          status: ['pending', 'approved', 'rejected', 'revoked'].includes(k.status) ? k.status : 'pending',
          approved: k.approved === true,
          reviewNotes: str(k.reviewNotes) || null,
          submittedAt: toDate(k.submittedAt) || new Date(u.updateTime?.toMillis?.() || Date.now()),
          reviewedAt: toDate(k.reviewedAt),
          revokedAt: toDate(k.revokedAt),
        },
      });
      created++;
    } catch (e) {
      errored++;
      console.error(`[kyc] skip ${u.id}: ${e.message}`);
    }
  }
  console.log(`[kyc] done. eligible=processed created=${created} errors=${errored}`);
}

async function backfillNotifications() {
  const snap = await fs.collection('notifications').get();
  let created = 0, skipped = 0, noUser = 0, errored = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const firebaseUid = str(d.userId);
    if (!firebaseUid) { skipped++; continue; }
    const user = await prisma.user.findUnique({
      where: { firebaseUid },
      select: { id: true },
    });
    if (!user) { noUser++; continue; }
    const exists = await prisma.notification.findFirst({
      where: {
        userId: user.id,
        type: str(d.type) || 'general',
        title: d.title ? String(d.title) : null,
        body: d.body ? String(d.body) : null,
      },
      select: { id: true },
    });
    if (exists) { skipped++; continue; }
    if (!COMMIT) { created++; continue; }
    try {
      await prisma.notification.create({
        data: {
          userId: user.id,
          type: str(d.type) || 'general',
          title: d.title ? String(d.title) : null,
          body: d.body ? String(d.body) : null,
          data: (d.data && typeof d.data === 'object') ? d.data : {},
          readAt: d.isRead === true ? toDate(d.createdAt) || new Date() : null,
          createdAt: toDate(d.createdAt) || new Date(d.createdAt?.toMillis?.() || Date.now()),
        },
      });
      created++;
    } catch (e) {
      errored++;
      console.error(`[notifications] skip ${doc.id}: ${e.message}`);
    }
  }
  console.log(`[notifications] done. total=${snap.size} created=${created} skipped=${skipped} no_user=${noUser} errors=${errored}`);
}

(async () => {
  console.log(`mode=${COMMIT ? 'COMMIT' : 'DRY-RUN'}`);
  await backfillReviews();
  await backfillKyc();
  await backfillNotifications();
  await prisma.$disconnect();
  await admin.app().delete();
})().catch(async (e) => { console.error('FATAL:', e); await prisma.$disconnect(); process.exit(1); });