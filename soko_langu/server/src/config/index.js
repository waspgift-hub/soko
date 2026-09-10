const config = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT) || 3000,
  
  // Firebase
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    serviceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
  },
  
  // Database
  database: {
    url: process.env.DATABASE_URL || 'postgresql://sokovibe:password@localhost:5432/sokovibe',
  },
  
  // Redis
  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
  },
  
  // Cloudflare R2
  r2: {
    accountId: process.env.R2_ACCOUNT_ID,
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    bucketImages: process.env.R2_BUCKET_IMAGES || 'soko-vibe-images',
    bucketVideos: process.env.R2_BUCKET_VIDEOS || 'soko-vibe-videos',
    bucketThumbnails: process.env.R2_BUCKET_THUMBNAILS || 'soko-vibe-thumbnails',
    bucketBackups: process.env.R2_BUCKET_BACKUPS || 'soko-vibe-backups',
    publicUrl: process.env.R2_PUBLIC_URL || 'https://media.soko-vibe.co.tz',
  },
  
  // Payment (ClickPesa)
  clickpesa: {
    apiUrl: process.env.CLICKPESA_API_URL,
    apiKey: process.env.CLICKPESA_API_KEY,
    apiSecret: process.env.CLICKPESA_API_SECRET,
    webhookSecret: process.env.CLICKPESA_WEBHOOK_SECRET,
    checksumKey: process.env.CLICKPESA_CHECKSUM_KEY,
    allowedIps: process.env.CLICKPESA_ALLOWED_IPS?.split(',').map(s => s.trim()) || [],
  },
  
  // SMS
  sms: {
    mesejiApiKey: process.env.MESEJI_API_KEY,
    mesejiSenderId: process.env.MESEJI_SENDER_ID || 'MESEJI',
    notifyAfricaApiKey: process.env.NOTIFY_AFRICA_API_KEY,
  },
  
  // Push Notifications
  onesignal: {
    appId: process.env.ONE_SIGNAL_APP_ID,
    apiKey: process.env.ONE_SIGNAL_REST_API_KEY,
  },
  
  // AI
  groq: {
    apiKey: process.env.GROQ_API_KEY,
  },
  
  // Security
  security: {
    adminSecret: process.env.ADMIN_SECRET,
    webhookSecret: process.env.WEBHOOK_SECRET,
    encryptionKey: process.env.ENCRYPTION_KEY,
    corsOrigins: process.env.ALLOWED_ORIGINS?.split(',').map(s => s.trim()) || [],
  },
  
  // Rate Limiting
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 900000,
    max: parseInt(process.env.RATE_LIMIT_MAX) || 100,
  },
  
  // Business
  business: {
    // Product-owner rule: Soko Vibe charges NO platform fee; only ClickPesa's
    // own charges apply (collected/deducted by ClickPesa outside our ledger).
    platformCommissionPercent: parseFloat(process.env.PLATFORM_COMMISSION_PERCENT) || 0,
    escrowAutoReleaseDays: parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 14,
    maxDailySaleAmount: parseInt(process.env.MAX_DAILY_SALE_AMOUNT) || 5000000,
  },

  // Finance safety-net scheduler. All jobs are idempotent (state-machine
  // guards + unique keys), so overlapping instances are safe.
  finance: {
    // Run the finance BullMQ worker inside the API process (current single
    // instance). Set FINANCE_WORKER_IN_PROCESS=false when a dedicated worker
    // process is deployed so both never double-process (BullMQ also guards).
    workerInProcess: process.env.FINANCE_WORKER_IN_PROCESS !== 'false',
    paymentExpireMs: (parseInt(process.env.FINANCE_PAYMENT_EXPIRE_MS) || 24 * 3600) * 1000,
    autoReleaseDays: parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 14,
    withdrawalAutoProcessMs: (parseInt(process.env.FINANCE_WITHDRAWAL_AUTO_PROCESS_MIN) || 15) * 60 * 1000,
    withdrawalStuckMs: (parseInt(process.env.FINANCE_WITHDRAWAL_STUCK_HOURS) || 48) * 3600 * 1000,
    reconciliationWindowMs: (parseInt(process.env.FINANCE_RECONCILIATION_WINDOW_HOURS) || 24) * 3600 * 1000,
    disputeSlaMs: (parseInt(process.env.FINANCE_DISPUTE_SLA_HOURS) || 72) * 3600 * 1000,
  },
  
  // URLs
  urls: {
    app: process.env.APP_URL || 'https://api.soko-vibe.co.tz',
    frontend: process.env.FRONTEND_URL || 'https://soko-vibe.co.tz',
    admin: process.env.ADMIN_URL || 'https://admin.soko-vibe.co.tz',
  },

  // Deep-link store destinations. Left empty on purpose: the app is not yet
  // listed on any store, so the fallback page must not advertise one. Once a
  // real listing exists, set ANDROID_STORE_URL / IOS_STORE_URL in the env.
  deepLink: {
    androidStoreUrl: process.env.ANDROID_STORE_URL || '',
    iosStoreUrl: process.env.IOS_STORE_URL || '',
    webProductUrl: process.env.WEB_PRODUCT_URL || 'https://www.sokovibe.co.tz/product/',
  },
};

module.exports = config;
