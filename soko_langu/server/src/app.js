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
const { seoRouter, NOT_FOUND_HTML } = require('./seo/routes');

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
  // Sparse CSP: the API (JSON) is locked down, but the marketing pages, legal
  // pages and the browser admin dashboard pull Firebase/Google, Tailwind,
  // chart.js, lucide, and Google Fonts from CDNs — those hosts are
  // allow-listed instead of falling back to unsafe-inline-everything.
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com https://www.googleapis.com https://apis.google.com https://cdn.tailwindcss.com https://cdn.jsdelivr.net https://unpkg.com https://pagead2.googlesyndication.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://accounts.google.com https://googleads.g.doubleclick.net https://pagead2.googlesyndication.com https://www.gstatic.com https://www.googleapis.com https://firestore.googleapis.com https://firebasestorage.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; media-src 'self' blob: https:; worker-src 'self' blob:");
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  next();
});

// Canonical domain: www.sokovibe.co.tz is the official host. Render redirects
// the apex (sokovibe.co.tz) to www at the edge before the app; if a request
// ever reaches the app on the apex (e.g. the edge redirect is removed) we
// still fold it onto www ourselves — unless SERVE_APEX=1, in which case the
// apex serves the SAME landing site directly (canonical/og tags stay www).
// Other sokovibe.co.tz subdomains are folded onto www too (path + query
// preserved). The admin subdomain keeps its root->/admin mapping. Non-Soko
// hosts (Render origin, health checks) are left alone so the platform health
// checks stay 200.
const CANONICAL_HOST = 'https://www.sokovibe.co.tz';
const DOMAIN = 'sokovibe.co.tz';
const WWW_HOST = `www.${DOMAIN}`;
const SERVE_APEX = process.env.SERVE_APEX === '1';

app.use((req, res, next) => {
  const host = (req.hostname || '').toLowerCase();
  if (!host.endsWith(DOMAIN)) return next();
  if (host === `admin.${DOMAIN}` || host === `www.admin.${DOMAIN}`) {
    return res.redirect(301, `${CANONICAL_HOST}/admin${req.path === '/' ? '' : req.path}`);
  }
  if (host === DOMAIN) {
    if (SERVE_APEX) return next();
    return res.redirect(301, `${CANONICAL_HOST}${req.originalUrl}`);
  }
  if (host === `admin.${DOMAIN}` && (req.path === '/' || req.path === '')) {
    return res.redirect(301, `${CANONICAL_HOST}/admin`);
  }
  if (host !== WWW_HOST) {
    return res.redirect(301, `${CANONICAL_HOST}${req.originalUrl}`);
  }
  next();
});

// HTTPS-only canonicalization: if a request ever reaches the app over plain
// HTTP on the public domain (e.g. an edge redirect is removed), fold it onto
// HTTPS with a 301. Localhost and non-domain hosts are left untouched so local
// dev and platform health checks keep working over HTTP.
app.use((req, res, next) => {
  const host = (req.hostname || '').toLowerCase();
  if (host.endsWith(DOMAIN) && req.protocol === 'http') {
    return res.redirect(301, `https://${req.get('host')}${req.originalUrl}`);
  }
  next();
});

// Canonical URL normalization: collapse trailing-slash variants of public
// pages (e.g. /about/ -> /about) with a 301 so each page has exactly one URL.
// API, health and .well-known paths are excluded to avoid interfering with
// health checks, app-link validation and JSON endpoints.
app.use((req, res, next) => {
  const path = req.path;
  if (
    path.length > 1 &&
    path.endsWith('/') &&
    !path.startsWith('/api') &&
    !path.startsWith('/health') &&
    !path.startsWith('/.well-known') &&
    !path.startsWith('/admin')
  ) {
    return res.redirect(301, path.slice(0, -1) + req.originalUrl.slice(path.length));
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

// Public assets: browser admin dashboard at /admin and the landing site at /
// (the landing files mirror the Firebase Hosting site). The admin hostname is
// redirected to /admin so the bare domain lands on the panel; every other host
// gets the landing page.
app.get('/', (req, res, next) => {
  if ((req.hostname || '').endsWith('admin.sokovibe.co.tz')) return res.redirect(301, '/admin');
  next();
});

// Universal/App Links verification files for the native apps. Served with an
// explicit JSON content-type because apple-app-site-association has no file
// extension and express.static would otherwise send application/octet-stream.
const landingDir = path.join(__dirname, '..', 'landing');
const wellKnownDir = path.join(landingDir, '.well-known');
app.get('/.well-known/assetlinks.json', (req, res) => {
  res.type('application/json').sendFile(path.join(wellKnownDir, 'assetlinks.json'));
});
app.get('/.well-known/apple-app-site-association', (req, res) => {
  res.type('application/json').sendFile(path.join(wellKnownDir, 'apple-app-site-association'));
});
app.get('/.well-known/apple-app-site-association.json', (req, res) => {
  res.type('application/json').sendFile(path.join(wellKnownDir, 'apple-app-site-association'));
});

// SEO assets: robots.txt + sitemap.xml (static, no Firestore).
app.use(seoRouter);

// Public marketing/legal pages on clean URLs. Served from the landing dir so
// their relative asset + translation links resolve (styles.css, i18n.js, index.html).
const PUBLIC_HTML_PAGES = [
  ['/privacy-policy', 'privacy.html'],
  ['/terms-of-service', 'terms.html'],
  ['/support', 'support.html'],
  ['/tanzania-marketplace', 'tanzania-marketplace.html'],
  ['/categories', 'categories.html'],
  ['/how-soko-vibe-works', 'how-soko-vibe-works.html'],
  ['/soko-vibe-fees', 'soko-vibe-fees.html'],
  ['/soko-vibe-escrow', 'soko-vibe-escrow.html'],
  ['/about', 'about.html'],
  ['/about/founder', 'about-founder.html'],
];
for (const [route, file] of PUBLIC_HTML_PAGES) {
  app.get(route, (req, res) => {
    res.setHeader('Cache-Control', 'no-cache');
    if (!req.accepts('html')) return res.status(406).type('text/plain').send('Not acceptable');
    res.type('html').sendFile(path.join(landingDir, file));
  });
}

// /marketing used to host the old landing; the site now owns the root.
app.use('/marketing', (req, res) => {
  res.redirect(301, '/');
});

app.use('/admin', express.static(path.join(__dirname, '..', 'admin'), { index: 'index.html' }));

// The landing page owns the root. HTML is never cached so edits go live
// immediately; versioned assets (css/js/png/ico/json) cache hard.
// Brand/favicon images must stay revalidatable (no-cache) so an icon swap
// goes live without renaming files or waiting out a 1-year immutable cache.
const landingIconNames = new Set([
  'favicon.ico', 'favicon.png', 'favicon-16.png', 'favicon-32.png',
  'apple-touch-icon.png', 'icon-192.png', 'icon-512.png', 'logo.png',
]);
app.use(express.static(landingDir, {
  index: 'index.html',
  setHeaders: (res, filePath) => {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.html' || filePath.endsWith('manifest.json')) {
      res.setHeader('Cache-Control', 'no-cache');
    } else if (landingIconNames.has(path.basename(filePath))) {
      res.setHeader('Cache-Control', 'no-cache');
    } else {
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    }
  },
}));

// Browsers/bots often request /favicon.ico directly regardless of the <link>
// tags — map the root one to the brand favicon instead of serving a 404.
app.get('/favicon.ico', (req, res) => res.redirect('/assets/favicon.ico'));

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
  app.use('/api/admin', generalLimiter, compat.adminCompatRouter);
  console.log('[COMPAT] legacy routers mounted');
} catch (e) {
  console.error('[COMPAT] mount failed, v1 continues:', e.message);
}

// Final 404: JSON for API routes, premium HTML page for everything else.
app.use((req, res) => {
  if (req.path.startsWith('/api') || req.path.startsWith('/health')) {
    if (!req.accepts('json') && req.accepts('html')) {
      return res.status(404).setHeader('Cache-Control', 'no-cache').type('html').send(NOT_FOUND_HTML);
    }
    return res.status(404).json({ error: 'Not found' });
  }
  if (!req.accepts('html')) {
    return res.status(404).type('text/plain').send('Not found');
  }
  res.status(404).setHeader('Cache-Control', 'no-cache').type('html').send(NOT_FOUND_HTML);
});

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