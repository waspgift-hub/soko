const express = require('express');
const path = require('path');
const compression = require('compression');
const cors = require('cors');
const config = require('./config');
const { connectDatabase } = require('./config/database');
const { connectRedis } = require('./config/redis');
const healthRouter = require('./modules/health/routes');
const authRouter = require('./modules/auth/routes');
const userSettingsRouter = require('./modules/users/routes');
const sellerRouter = require('./modules/sellers/routes');
const orderRouter = require('./modules/orders/routes');
const paymentRouter = require('./modules/payments/routes');
const shippingRouter = require('./modules/shipping/routes');
const handoverRouter = require('./modules/handover/routes');
const walletRouter = require('./modules/wallet/routes');
const disputeRouter = require('./modules/disputes/routes');
const mediaRouter = require('./modules/media/routes');
const feedRouter = require('./modules/feed/routes');
const searchRouter = require('./modules/search/routes');
const sharingRouter = require('./modules/sharing/routes');
const trustRouter = require('./modules/trust/routes');
const adminRouter = require('./modules/admin/routes');
const productRouter = require('./modules/products/routes');
const referralRouter = require('./modules/referrals/routes');
const moderationRouter = require('./modules/moderation/routes');
const reconciliationRouter = require('./modules/reconciliation/routes');

const app = express();

// Trust proxy for Nginx
app.set('trust proxy', 1);

// Compression
app.use(compression());

// Security headers
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  // Sparse CSP: same-origin API stays locked down, but the public marketing
  // pages + admin dashboard pull Firebase/Google, Tailwind, chart.js, lucide,
  // Google Fonts, and AdSense from CDNs — those hosts are allow-listed instead
  // of falling back to unsafe-inline-everything.
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' https://www.gstatic.com https://www.googleapis.com https://apis.google.com https://cdn.tailwindcss.com https://cdn.jsdelivr.net https://unpkg.com https://pagead2.googlesyndication.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://accounts.google.com https://googleads.g.doubleclick.net https://pagead2.googlesyndication.com; font-src 'self' data: https://fonts.gstatic.com");
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  next();
});

// CORS
app.use(cors({
  origin: (origin, cb) => {
    if (!origin || config.security.corsOrigins.includes(origin)) {
      return cb(null, true);
    }
    cb(null, false);
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-admin-secret'],
  credentials: false,
  maxAge: 86400,
}));

// Body parsing
app.use(express.json({ limit: '10mb' }));

// Request timeout
app.use((req, res, next) => {
  res.setTimeout(20000, () => {
    res.status(504).json({ error: 'Request timed out' });
  });
  next();
});

// Public assets: browser admin dashboard at /admin and the marketing site at
// / (the landing files mirror the Firebase Hosting site). The admin hostname
// is redirected to /admin so the bare domain lands on the panel; every other
// host gets the marketing page.
app.get('/', (req, res, next) => {
  if ((req.hostname || '').endsWith('admin.sokovibe.co.tz')) return res.redirect(301, '/admin');
  next();
});
app.use(express.static(path.join(__dirname, '..', 'landing'), { index: 'index.html' }));
app.use('/admin', express.static(path.join(__dirname, '..', 'admin'), { index: 'index.html' }));

// Routes
app.use('/health', healthRouter);
app.use('/api/v1/auth', authRouter);
app.use('/api/v1/users/settings', userSettingsRouter);
app.use('/api/v1/sellers', sellerRouter);
app.use('/api/v1/orders', orderRouter);
app.use('/api/v1/payments', paymentRouter);
app.use('/api/v1/shipping', shippingRouter);
app.use('/api/v1/handover', handoverRouter);
app.use('/api/v1/wallet', walletRouter);
app.use('/api/v1/disputes', disputeRouter);
app.use('/api/v1/media', mediaRouter);
app.use('/api/v1/feed', feedRouter);
app.use('/api/v1/search', searchRouter);
app.use('/api/v1/share', sharingRouter);
app.use('/api/v1/trust', trustRouter);
app.use('/api/v1/admin', adminRouter);
app.use('/api/v1/products', productRouter);
app.use('/api/v1/referrals', referralRouter);
app.use('/api/v1/moderation', moderationRouter);
app.use('/api/v1/reconciliation', reconciliationRouter);

// Legacy-compat: proven old routers under original /api paths (payouts,
// delivery OTP, search, notifications). Firestore is the same project, so
// existing app versions keep working with zero client changes.
try {
  const { setupCompat } = require('./modules/legacy-compat/compat');
  const { generalLimiter, searchLimiter } = require('./middleware/rateLimiter');
  const compat = setupCompat(app);
  app.use('/api', generalLimiter, compat.payoutsRouter);
  app.use('/api/orders', generalLimiter, compat.deliveryRouter);
  app.use('/api/search', searchLimiter, compat.searchRouter);
  app.use('/api/notification', generalLimiter, compat.notificationRouter);
  app.use('/api/escrow', generalLimiter, compat.escrowRouter);
  app.use('/api', generalLimiter, compat.ordersCompatRouter);
  app.use('/api', generalLimiter, compat.moderationCompatRouter);
  console.log('[COMPAT] legacy routers mounted');
} catch (e) {
  console.error('[COMPAT] mount failed, v1 continues:', e.message);
}

// Error handler
app.use((err, req, res, next) => {
  console.error('[ERROR]', err.message);
  res.status(err.status || 500).json({ 
    error: config.nodeEnv === 'development' ? err.message : 'Internal server error' 
  });
});

// Initialize connections
async function initialize() {
  await connectDatabase();
  await connectRedis();
}

module.exports = { app, initialize };
