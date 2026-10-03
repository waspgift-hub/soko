// Express 4 swallows rejected promises from async route handlers, leaving
// requests hanging until the proxy gives up (504). Patch Layer#handle_request
// before any route mounts so async rejections reach the error handler below.
require('./utils/express-async');

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
  const userProfileRouter = userSettingsRouter.profileRouter;
const sellerRouter = require('./modules/sellers/routes');
const orderRouter = require('./modules/orders/routes');
const paymentRouter = require('./modules/payments/routes');
const shippingRouter = require('./modules/shipping/routes');
const handoverRouter = require('./modules/handover/routes');
const walletRouter = require('./modules/wallet/routes');
const disputeRouter = require('./modules/disputes/routes');
const refundRouter = require('./modules/refunds/routes');
const mediaRouter = require('./modules/media/routes');
const feedRouter = require('./modules/feed/routes');
const searchRouter = require('./modules/search/routes');
const aiRouter = require('./modules/ai/routes');
const sharingRouter = require('./modules/sharing/routes');
const trustRouter = require('./modules/trust/routes');
const adminRouter = require('./modules/admin/routes');
// KYC identity documents. Mounted BEFORE the general admin router so its own
// gate (secret OR database-verified admin role) is the one that runs; the
// secret-only `authenticateAdmin` on adminRouter is left untouched.
const adminKycRouter = require('./modules/admin/kyc-documents-routes');
// Advertising configuration and Blue Tick grant/revoke. Mounted before the
// general admin router so these routes are reachable without going through the
// broader admin surface; the router carries its own authenticateAdmin gate.
const adsAdminRouter = require('./modules/ads/routes');
const productRouter = require('./modules/products/routes');
const referralRouter = require('./modules/referrals/routes');
const moderationRouter = require('./modules/moderation/routes');
const reconciliationRouter = require('./modules/reconciliation/routes');
const notificationRouter = require('./modules/notifications/routes');
const sellerAnalyticsRouter = require('./modules/seller-analytics/routes');
const youtubeRouter = require('./modules/youtube/routes');
const musicRouter = require('./modules/music/routes');
const reviewRouter = require('./modules/reviews/routes');
const commentsRouter = require('./modules/comments/routes');
const kycRouter = require('./modules/kyc/routes');
const deletionRequestRouter = require('./modules/data-deletion/routes');
const { seoRouter, NOT_FOUND_HTML } = require('./seo/routes');
const legacyShopRouter = require('./modules/legacy-shop/routes');
const requestId = require('./middleware/requestId');
const { jsonError } = require('./utils/http');

// BigInt is used for TZS money in DB rows (store Decimal->string->BigInt).
// Express res.json() cannot serialize BigInt â€” TZS fits a JS safe integer
// (max ~9e15), so serialize to Number before responding.
BigInt.prototype.toJSON = function toJSON() {
  return Number(this);
};

const app = express();

// Never fingerprint the stack: Express sends `X-Powered-By: Express` by
// default, which hands scanners a version oracle for free. The edge strips it
// too, but defence starts at the origin (direct-to-Render traffic included).
app.disable('x-powered-by');

// Trust proxy for Nginx
app.set('trust proxy', 1);

// Load shedder must run FIRST: it answers 503 before any handler can spend
// effort on a request when the event loop or heap is saturated.
const { loadShedder } = require('./middleware/loadShedder');
app.use(loadShedder());

// API contract §25: one id per request, echoed on every JSON response.
app.use(requestId);

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
  // chart.js, lucide, and Google Fonts from CDNs â€” those hosts are
  // allow-listed instead of falling back to unsafe-inline-everything.
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com https://www.googleapis.com https://apis.google.com https://cdn.tailwindcss.com https://cdn.jsdelivr.net https://unpkg.com https://pagead2.googlesyndication.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://accounts.google.com https://googleads.g.doubleclick.net https://pagead2.googlesyndication.com https://www.gstatic.com https://www.googleapis.com https://firestore.googleapis.com https://firebasestorage.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; media-src 'self' blob: https:; worker-src 'self' blob:");
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  next();
});

// Usage analytics: count every /api hit for request-rate stats (per min /
// hour / day / month / year). Fire-and-forget inside the service â€” it never
// blocks or fails requests, and skips silently when Redis is unreachable.
const { recordApiHit } = require('./services/activity');
app.use((req, res, next) => {
  if (req.path && req.path.startsWith('/api')) recordApiHit();
  next();
});

// Canonical domain: www.sokovibe.co.tz is the official host. Render redirects
// the apex (sokovibe.co.tz) to www at the edge before the app; if a request
// ever reaches the app on the apex (e.g. the edge redirect is removed) we
// still fold it onto www ourselves â€” unless SERVE_APEX=1, in which case the
// apex serves the SAME landing site directly (canonical/og tags stay www).
// Other sokovibe.co.tz subdomains are folded onto www too (path + query
// preserved). The admin subdomain serves the browser panel directly at its
// root: every non-API path is rewritten onto the /admin static mount so
// admin.sokovibe.co.tz/ == admin.sokovibe.co.tz/admin == .../admin on www.
// The api subdomain is the edge-cached API host (Cloudflare Worker in front),
// so it passes through untouched. Non-Soko hosts (Render origin, health
// checks) are left alone so the platform health checks stay 200.
const CANONICAL_HOST = 'https://www.sokovibe.co.tz';
const DOMAIN = 'sokovibe.co.tz';
const WWW_HOST = `www.${DOMAIN}`;
const SERVE_APEX = process.env.SERVE_APEX === '1';

app.use((req, res, next) => {
  const host = (req.hostname || '').toLowerCase();
  if (!host.endsWith(DOMAIN)) return next();
  if (host === `admin.${DOMAIN}` || host === `www.admin.${DOMAIN}`) {
    const p = req.path;
    // API, health and app-link paths pass through so the admin host can also
    // be used as an API endpoint if needed; everything else is the panel.
    if (p.startsWith('/api') || p.startsWith('/health') || p.startsWith('/.well-known')) return next();
    const q = req.originalUrl.includes('?') ? req.originalUrl.slice(req.originalUrl.indexOf('?')) : '';
    // Rewrite onto the /admin static mount, but never double-prefix: the panel
    // already uses absolute /admin/* asset paths that must survive unchanged.
    req.url = `${p.startsWith('/admin') ? '' : '/admin'}${p === '/' ? '/' : p}${q}`;
    return next();
  }
  // api host is dedicated to the API edge worker â€” never fold onto www.
  if (host === `api.${DOMAIN}` || host === `www.api.${DOMAIN}`) return next();
  if (host === DOMAIN) {
    if (SERVE_APEX) return next();
    return res.redirect(301, `${CANONICAL_HOST}${req.originalUrl}`);
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

// Body parsing. Image/video bytes never travel in a JSON body anymore (presigned
// R2 PUT / direct Cloudinary upload), so 1mb is generous for every v1 payload —
// the old 10mb let an unauthenticated client force a 10mb JSON parse per request.
app.use(express.json({ limit: '1mb' }));

// Request timeout + start timestamp.
//
// `_startTime` is recorded here (before any route work) and consumed by both
// the metrics middleware and the error handler, so a latency number and the log
// line for the same failure always agree.
app.use((req, res, next) => {
  req._startTime = Date.now();
  res.setTimeout(20000, () => {
    jsonError(res, { status: 504, code: 'REQUEST_TIMED_OUT', message: 'Request timed out' });
  });
  next();
});

// Public assets: browser admin dashboard at /admin and the landing site at /
// (the landing files mirror the Firebase Hosting site). The admin hostname is
// rewritten onto /admin above, so the bare domain lands on the panel; every
// other host gets the landing page.

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
  ['/data-deletion', 'deletion.html'],
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

// /shop served the retired web-shop SPA; fold it onto the landing root so
// old bookmarks and links land somewhere useful instead of a 404.
app.use('/shop', (req, res) => {
  res.redirect(301, '/');
});

app.use('/admin', express.static(path.join(__dirname, '..', 'admin'), { index: 'index.html' }));
  // Old panel URLs redirect to the real panel so nobody lands on a stale page.
  app.get(['/admin.html', '/dashboard', '/admin/index.html'], (req, res) => res.redirect(301, '/admin/'));

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

// Web fallback routes for deep links (must be before static so /product/:id serves HTML)
const fallbackRouter = require('./modules/sharing/fallback-routes');
app.use('/', fallbackRouter);

// Routes
// Per-IP ceilings for the whole v1 surface (trust proxy is 1 hop, so req.ip is
// the real client behind the Cloudflare worker). Admin gets a wider own limiter
// so an auth/crawler loop against one endpoint can't exhaust the general one.
const { generalLimiter, adminLimiter, aiLimiter, lyricsLimiter } = require('./middleware/rateLimiter');
app.use('/api/v1', generalLimiter);
app.use('/api/v1/admin', adminLimiter);
app.use('/health', healthRouter);
app.use('/api/v1/auth', authRouter);
app.use('/api/v1/users/settings', userSettingsRouter);
  app.use('/api/v1/users', userProfileRouter);
app.use('/api/v1/sellers', sellerRouter);
app.use('/api/v1/orders', orderRouter);
app.use('/api/v1/payments', paymentRouter);
app.use('/api/v1/shipping', shippingRouter);
app.use('/api/v1/handover', handoverRouter);
app.use('/api/v1/wallet', walletRouter);
app.use('/api/v1/disputes', disputeRouter);
app.use('/api/v1/refunds', refundRouter);
app.use('/api/v1/media', mediaRouter);
app.use('/api/v1/feed', feedRouter);
app.use('/api/v1/search', searchRouter);
app.use('/api/v1/share', sharingRouter);
app.use('/api/v1/trust', trustRouter);
app.use('/api/v1/admin/kyc', adminKycRouter);
app.use('/api/v1/admin', adsAdminRouter);
app.use('/api/v1/admin', adminRouter);
app.use('/api/v1/products', productRouter);
app.use('/api/v1/referrals', referralRouter);
app.use('/api/v1/moderation', moderationRouter);
app.use('/api/v1/data-deletion', deletionRequestRouter);
app.use('/api/v1/reconciliation', reconciliationRouter);
app.use('/api/v1/notifications', notificationRouter);
app.use('/api/v1', sellerAnalyticsRouter);
app.use('/api/v1/youtube', youtubeRouter);
// Rate limited per user because the lyrics AI fallback spends provider tokens.
app.use('/api/v1/music', lyricsLimiter, musicRouter);
app.use('/api/v1/reviews', reviewRouter);
  app.use('/api/v1', commentsRouter);
  app.use('/api/v1/kyc', kycRouter);

// Legacy web-shop: v2-backed checkout/status under the ORIGINAL /api paths so
// the shop SPA needs no client change. Mounted before legacy-compat; both mount
// groups resolve to the same Firestore store seam via getStore().
// generalLimiter/aiLimiter are hoisted at the v1 block above.
// AI proxy: the app sends an OpenAI-shaped payload plus its Firebase token;
// the server injects provider keys and fails over Groq -> Gemini. Mounted on
// the ORIGINAL /api/ai/* paths (not /api/v1) so the shipped app needs no change.
app.use('/api/ai', aiLimiter, aiRouter);
console.log('[AI] providers:', JSON.stringify(aiRouter.gatewayStatus()));
app.use('/api', generalLimiter, legacyShopRouter);

// Legacy-compat: proven old routers under original /api paths (payouts,
// delivery OTP, search, notifications). Firestore is the same project, so
// existing app versions keep working with zero client changes.
try {
  const { setupCompat } = require('./modules/legacy-compat/compat');
  const { searchLimiter, adminLimiter } = require('./middleware/rateLimiter');
  const compat = setupCompat(app);
  app.use('/api', generalLimiter, compat.payoutsRouter);
  // The shop SPA posts to /api/payouts/seller/withdraw; the legacy mount above
  // served it as /api/seller/withdraw only. Same router, second path prefix.
  app.use('/api/payouts', generalLimiter, compat.payoutsRouter);
  app.use('/api/orders', generalLimiter, compat.deliveryRouter);
  app.use('/api/search', searchLimiter, compat.searchRouter);
  app.use('/api/notification', generalLimiter, compat.notificationRouter);
  app.use('/api/notifications', generalLimiter, compat.notificationRouter);
  app.use('/api', generalLimiter, compat.featureCompatRouter);
  app.use('/api/escrow', generalLimiter, compat.escrowRouter);
  app.use('/api', generalLimiter, compat.ordersCompatRouter);
  app.use('/api', generalLimiter, compat.trustCompatRouter);
  app.use('/api', generalLimiter, compat.moderationCompatRouter);
  app.use('/api/admin', adminLimiter, compat.adminCompatRouter);
  app.use('/api', adminLimiter, compat.adminCompatPublic);
  console.log('[COMPAT] legacy routers mounted (incl. feature-compat)');
} catch (e) {
  console.error('[COMPAT] mount failed, v1 continues:', e.message);
}

// Final 404: JSON for API routes, premium HTML page for everything else.
app.use((req, res) => {
  if (req.path.startsWith('/api') || req.path.startsWith('/health')) {
    if (!req.accepts('json') && req.accepts('html')) {
      return res.status(404).setHeader('Cache-Control', 'no-cache').type('html').send(NOT_FOUND_HTML);
    }
    return jsonError(res, { status: 404, code: 'NOT_FOUND', message: 'Not found' });
  }
  if (!req.accepts('html')) {
    return res.status(404).type('text/plain').send('Not found');
  }
  res.status(404).setHeader('Cache-Control', 'no-cache').type('html').send(NOT_FOUND_HTML);
});

// Error handler
//
// Every line is correlated by `requestId`, which the client already receives in
// the error envelope (utils/http.js:14). Before this, the handler logged only
// `err.message`, so a user reporting "it failed, here is my ID SF-abc123" could
// not be matched to a single line in the logs. The ID is now the first field.
app.use((err, req, res, next) => {
  const startedAt = req._startTime || Date.now();
  const durationMs = Date.now() - startedAt;
  const status = err.status || err.statusCode || 500;

  console.error(
    JSON.stringify({
      level: 'error',
      requestId: req.id || null,
      method: req.method,
      path: req.originalUrl || req.url,
      status,
      errorName: err.name || 'Error',
      // The message can contain an operator id or a provider payload; it is
      // the single most useful field for triage and this stream is not shipped
      // to clients, so it stays in full.
      message: err.message,
      durationMs,
      ...(err.code ? { code: err.code } : {}),
      ...(err.lockReason ? { lockReason: err.lockReason } : {}),
      ...(process.env.NODE_ENV !== 'production' && err.stack
        ? { stack: err.stack.split('\n').slice(0, 6).join('\n') }
        : {}),
    }),
  );

  // A lock or Redis outage is transient by nature: tell the client to retry
  // instead of showing a generic failure.
  if (err.code === 'LOCK_UNAVAILABLE' || err.code === 'REDIS_UNAVAILABLE') {
    res.setHeader('Retry-After', '5');
  }

  const isDev = config.nodeEnv === 'development';
  jsonError(res, {
    status,
    code: err.code || 'INTERNAL_ERROR',
    message:
      status === 503 && !isDev
        ? 'Service temporarily unavailable, please retry'
        : isDev
          ? err.message
          : 'Internal server error',
  });
});

// Initialize connections
async function initialize() {
  await connectDatabase();
  await connectRedis();
}

module.exports = { app, initialize };
