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
const { seoRouter, handleSpa } = require('./seo/routes');

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
  // CSP covers three consumers on one server: the API (JSON), the marketing
  // pages, and the Flutter web app. CanvasKit needs wasm-unsafe-eval + blob
  // workers, and the web app talks to Firestore/Storage + Firebase auth
  // directly from the browser.
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com https://www.googleapis.com https://apis.google.com https://cdn.tailwindcss.com https://cdn.jsdelivr.net https://unpkg.com https://pagead2.googlesyndication.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://accounts.google.com https://googleads.g.doubleclick.net https://pagead2.googlesyndication.com https://www.gstatic.com https://www.googleapis.com https://firestore.googleapis.com https://firebasestorage.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; media-src 'self' blob: https:; worker-src 'self' blob:");
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  next();
});

// Canonical domain: every sokovibe.co.tz hostname is folded onto the www host
// (path + query preserved, one redirect hop). The admin subdomain keeps its
// root->/admin mapping. Non-soko hosts (Render origin, health checks) are left
// alone so the platform health checks stay 200.
app.use((req, res, next) => {
  const host = (req.hostname || '').toLowerCase();
  if (host.endsWith('sokovibe.co.tz') && host !== 'www.sokovibe.co.tz') {
    let target = req.originalUrl;
    if (host === 'admin.sokovibe.co.tz' && (target === '/' || target === '')) target = '/admin';
    return res.redirect(301, `https://www.sokovibe.co.tz${target}`);
  }
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

// Universal/App Links verification files. Served with an explicit JSON
// content-type because apple-app-site-association has no file extension and
// express.static would otherwise send application/octet-stream.
const wellKnownDir = path.join(__dirname, '..', 'landing', '.well-known');
const webDist = path.join(__dirname, '..', '..', 'build', 'web');
app.get('/.well-known/assetlinks.json', (req, res) => {
  res.type('application/json').sendFile(path.join(wellKnownDir, 'assetlinks.json'));
});
app.get('/.well-known/apple-app-site-association', (req, res) => {
  res.type('application/json').sendFile(path.join(wellKnownDir, 'apple-app-site-association'));
});
app.get('/.well-known/apple-app-site-association.json', (req, res) => {
  res.type('application/json').sendFile(path.join(wellKnownDir, 'apple-app-site-association'));
});

// SEO assets: robots.txt, sitemap.xml and the generated sitemap files.
app.use(seoRouter);

// The Flutter web app owns the root — www.sokovibe.co.tz now runs the app in
// the browser (guest browsing first, login + buy without installing). The
// legacy marketing landing moves under /marketing; /admin keeps its mount.
app.use('/marketing', express.static(path.join(__dirname, '..', 'landing'), { index: 'index.html' }));
app.use('/admin', express.static(path.join(__dirname, '..', 'admin'), { index: 'index.html' }));

// Flutter web build (committed under build/web so Render can serve it).
// index.html is served through the SPA handler below, where SEO metadata is
// injected; the rest is content-versioned by the service worker and cached hard
// to make repeat loads fast.
app.use(express.static(webDist, {
  index: false,
  setHeaders: (res, filePath) => {
    const name = path.basename(filePath);
    if (name === 'flutter_bootstrap.js' || name.includes('service_worker')) {
      res.setHeader('Cache-Control', 'no-cache');
    } else {
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    }
  },
}));

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

// SPA handler with server-side SEO: injected per-route metadata (products fetch
// real Firestore data so title/description/OG/JSON-LD match the page), genuine
// 404s for missing products and unknown paths. Mounted LAST so real routes
// (/health, /api/*, ...) always win over the SPA catch-all.
app.get('*', handleSpa);

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
