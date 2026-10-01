const { z } = require('zod');
const { jsonError } = require('../utils/http');

// The app sends the code as `otp` on some screens and `code` on others, so both
// are accepted — but exactly one is REQUIRED. Left optional, a body with
// neither passed schema validation and produced a generic "auth_otp_invalid",
// which reads to the user as "your code was wrong" when they never sent one.
const OTP_VALUE = z.string().regex(/^\d{6}$/, 'OTP must be 6 digits');
const withOtp = (extra = {}) => z.object({
  ...extra,
  otp: OTP_VALUE.optional(),
  code: OTP_VALUE.optional(),
}).refine((v) => Boolean(v.otp || v.code), {
  message: 'OTP code is required',
  path: ['otp'],
});

// Validation schemas
const schemas = {
  // Auth schemas
  sendOtp: z.object({
    phone: z.string().regex(/^(\+?255|0)[67]\d{8}$/, 'Invalid Tanzanian phone number'),
    langCode: z.enum(['sw', 'en']).optional(),
  }),

  // The email OTP routes previously had no schema at all, so sendEmailOtp
  // validated the address by hand and answered `{ error: 'Valid email required' }`
  // — a human sentence in the field every other route uses for a machine code,
  // which the app cannot switch on.
  sendEmailOtp: z.object({
    email: z.string().email('Invalid email address'),
    langCode: z.enum(['sw', 'en']).optional(),
  }),

  verifyEmailOtp: withOtp({
    email: z.string().email('Invalid email address'),
  }),

  verifyOtp: withOtp({
    phone: z.string().regex(/^(\+?255|0)[67]\d{8}$/, 'Invalid Tanzanian phone number'),
  }),

  phoneLogin: withOtp({
    phone: z.string().regex(/^(\+?255|0)[67]\d{8}$/, 'Invalid Tanzanian phone number'),
  }),

  resetPasswordByPhone: withOtp({
    phone: z.string().regex(/^(\+?255|0)[67]\d{8}$/, 'Invalid Tanzanian phone number'),
    newPassword: z.string().min(8, 'Password must be at least 8 characters'),
  }),

  // User schemas
  updateProfile: z.object({
    displayName: z.string().min(1).max(100).optional(),
    username: z.string().min(3).max(50).regex(/^[a-z0-9_]+$/, 'Username must be lowercase alphanumeric with underscores').optional(),
    bio: z.string().max(500).optional(),
    avatarUrl: z.string().url().optional(),
  }),

  // Product schemas
  createProduct: z.object({
    title: z.string().min(1).max(200),
    description: z.string().max(5000).optional(),
    price: z.number().positive().max(100000000),
    categoryId: z.string().uuid().optional(),
    stock: z.number().int().min(0).optional(),
    condition: z.enum(['new', 'like_new', 'good', 'fair']).optional(),
    weightGrams: z.number().int().positive().optional(),
  }),

  // Order schemas
  createOrder: z.object({
    productId: z.string().uuid(),
    quantity: z.number().int().positive().max(100),
    addressId: z.string().uuid(),
  }),

  // Shipping quote schemas
  createShippingQuote: z.object({
    orderId: z.string().uuid(),
    amount: z.number().positive().max(1000000),
    estimatedDays: z.number().int().positive().max(30),
    notes: z.string().max(500).optional(),
  }),

  // Pagination schemas
  pagination: z.object({
    cursor: z.string().optional(),
    limit: z.number().int().min(1).max(100).default(20),
  }),
};

// Validation middleware.
// Accepts a Zod schema (applied to req.body) OR an object mapping
// { body, query, params } to Zod schemas for composite validation.
function validate(schema) {
  return (req, res, next) => {
    const isZod = (s) => s && typeof s.safeParse === 'function';
    const targets = {};
    if (isZod(schema)) {
      targets.body = schema;
    } else {
      if (isZod(schema.body)) targets.body = schema.body;
      if (isZod(schema.query)) targets.query = schema.query;
      if (isZod(schema.params)) targets.params = schema.params;
    }

    const errors = [];

    for (const key of Object.keys(targets)) {
      if (!targets[key]) continue;
      const source = key === 'body' ? req.body : key === 'query' ? req.query : req.params;
      const result = targets[key].safeParse(source);

      if (!result.success) {
        errors.push(
          ...result.error.errors.map((err) => ({
            field: `${key}.${err.path.join('.')}`,
            message: err.message,
          }))
        );
      } else {
        // Backfill coerced/normalized values back onto the request source.
        if (key === 'body') req.body = result.data;
        else if (key === 'query') req.query = result.data;
        else req.params = result.data;
      }
    }

    if (errors.length > 0) {
      return jsonError(res, { status: 400, code: 'VALIDATION_ERROR', message: 'VALIDATION_ERROR', details: errors });
    }

    next();
  };
}

module.exports = { schemas, validate };
