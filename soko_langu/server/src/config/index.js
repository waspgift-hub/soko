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
    platformCommissionPercent: parseFloat(process.env.PLATFORM_COMMISSION_PERCENT) || 0.035,
    escrowAutoReleaseDays: parseInt(process.env.ESCROW_AUTO_RELEASE_DAYS) || 14,
    maxDailySaleAmount: parseInt(process.env.MAX_DAILY_SALE_AMOUNT) || 5000000,
  },
  
  // URLs
  urls: {
    app: process.env.APP_URL || 'https://api.soko-vibe.co.tz',
    frontend: process.env.FRONTEND_URL || 'https://soko-vibe.co.tz',
    admin: process.env.ADMIN_URL || 'https://admin.soko-vibe.co.tz',
  },
};

module.exports = config;
