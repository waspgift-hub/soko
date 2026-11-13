// Agent tool registry — every tool the Soko Vibe AI agent may invoke.
//
// Each tool spec is JSON-serialisable and describes:
//   name        — the function name the model may request
//   description — what it does, in plain language for the model
//   parameters  — JSON Schema input schema (the model is bound to this)
//   category    — account | product | order | wallet | support | notification | social
//   impact      — read | prepare | execute | destructive | financial
//   permissions — required agent permission scopes (bound to the authenticated account)
//   requiresApproval — whether an explicit pending-action approval is required BEFORE execution
//   requiresMfa — whether step-up authentication (MFA/reauth) is required
//   timeoutMs   — server-side execution timeout
//   retryable   — whether safe to auto-retry on transient failure
//   audit       — whether every invocation is audit-logged
//   run         — server-side implementation (never exposed to the model)
//
// Money-moving and destructive tools set requiresApproval=true and requiresMfa=true.
// Read tools never require approval. Prepare tools (draft creation) require approval
// only for the final mutation (publish/withdraw), not for the draft itself.

const {
  getStore,
} = require('../../config/database');
const productService = require('../products/product-service');
const orderService = require('../orders/order-service');
const walletService = require('../wallet/wallet-service');
const { searchWeb } = require('../ai/tavily');

const MAX_PRODUCTS = 6;
const MAX_ORDERS = 8;
const MAX_TRANSACTIONS = 20;
const TOOL_TIMEOUT_MS = 30_000;
const WITHDRAWAL_TIMEOUT_MS = 60_000;

function clip(value, max) {
  const s = typeof value === 'string' ? value : String(value ?? '');
  return s.length > max ? s.slice(0, max) + '…' : s;
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/*───────────────────────── Read tools ─────────────────────────*/

async function searchProductsAgent(args) {
  const query = clip(args.query, 120);
  if (!query) return { products: [], note: 'A query is required.' };
  const minPrice = Number.isFinite(args.min_price) ? args.min_price : undefined;
  const maxPrice = Number.isFinite(args.max_price) ? args.max_price : undefined;
  const searchService = require('../search/search-service');
  const { products, pagination } = await searchService.searchProducts({
    query,
    minPrice,
    maxPrice,
    limit: MAX_PRODUCTS,
  });
  return {
    query,
    total_matches: pagination?.total ?? products.length,
    products: products.map((p) => ({
      id: p.id,
      title: p.title ?? p.name ?? null,
      price: p.price ?? null,
      currency: p.currency ?? 'TZS',
      category: p.category?.name ?? p.category ?? null,
      location: p.location ?? p.district ?? null,
      seller: p.seller?.storeName ?? p.sellerName ?? null,
      in_stock: p.stock ?? null,
      rating: p.rating ?? null,
    })),
  };
}

async function getProductDetailsAgent(args) {
  if (!args.id) throw httpError(400, 'product id required');
  const productService = require('../products/product-service');
  const product = await productService.getProduct(args.id);
  return { product };
}

async function getMyProfileAgent(args, ctx) {
  if (!ctx.userId) return { note: 'No user record for this token.' };
  const store = getStore();
  const u = await store.user.findUnique({
    where: { id: ctx.userId },
    select: {
      displayName: true, email: true, phone: true, role: true,
      accountStatus: true, kycStatus: true, kycVerified: true, createdAt: true,
    },
  });
  if (!u) return { note: 'Profile not found.' };
  return {
    display_name: u.displayName ?? null,
    email: u.email ?? null,
    phone: u.phone ?? null,
    account_status: u.accountStatus ?? null,
    kyc_status: u.kycStatus ?? (u.kycVerified ? 'verified' : 'unverified'),
    is_seller: Boolean(ctx.sellerProfileId),
    member_since: u.createdAt ?? null,
  };
}

async function getMyOrdersAgent(args, ctx) {
  if (!ctx.userId) return { orders: [], note: 'No user record for this token.' };
  const store = getStore();
  const where = { OR: [{ buyerId: ctx.userId }] };
  if (ctx.sellerProfileId) where.OR.push({ sellerId: ctx.sellerProfileId });
  const wanted = ['pending', 'paid', 'shipped', 'delivered', 'cancelled', 'disputed'];
  const status = wanted.includes(String(args.status)) ? String(args.status) : null;
  if (status) where.status = status;
  const orders = await store.order.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    take: MAX_ORDERS,
  });
  return {
    filter: status || 'all',
    orders: (orders || []).map((o) => ({
      id: o.id,
      orderNumber: o.orderNumber ?? null,
      status: o.status ?? null,
      total: o.total ?? o.totalAmount ?? null,
      currency: o.currency ?? 'TZS',
      created_at: o.createdAt ?? null,
      role: o.buyerId === ctx.userId ? 'buyer' : 'seller',
    })),
  };
}

async function getMyWalletBalanceAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { note: 'No seller profile; wallets belong to sellers.' };
  const detail = await walletService.getWalletDetail(ctx.sellerProfileId, {
    page: 1, limit: 5,
  });
  return {
    available: detail.balances.available,
    pending: detail.balances.pending,
    frozen: detail.balances.frozen,
    totalEarned: detail.balances.totalEarned,
    totalWithdrawn: detail.balances.totalWithdrawn,
    currency: 'TZS',
  };
}

async function getMyTransactionsAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { transactions: [], note: 'No seller profile.' };
  const detail = await walletService.getWalletDetail(ctx.sellerProfileId, {
    page: 1, limit: MAX_TRANSACTIONS,
  });
  return {
    transactions: (detail.ledger || []).map((e) => ({
      id: e.id ?? null,
      type: e.type ?? null,
      amount: e.amount ?? null,
      balanceAfter: e.balanceAfter ?? null,
      description: e.description ?? null,
      createdAt: e.createdAt ?? null,
    })),
    pagination: detail.pagination ?? null,
  };
}

async function getMyNotificationsAgent(args, ctx) {
  if (!ctx.userId) return { notifications: [], note: 'No user record.' };
  const store = getStore();
  const items = await store.notification.findMany({
    where: { userId: ctx.userId },
    orderBy: { createdAt: 'desc' },
    take: 20,
  });
  return {
    notifications: (items || []).map((n) => ({
      id: n.id,
      type: n.type,
      title: n.title,
      body: n.body,
      read: Boolean(n.read),
      createdAt: n.createdAt,
    })),
  };
}

/*───────────────────────── Prepare tools (drafts) ─────────────────────────*/

async function createProductDraftAgent(args, ctx) {
  if (!ctx.sellerProfileId) {
    return { error: 'No seller profile. Become a seller before creating listings.' };
  }
  const data = {
    title: String(args.title || '').trim(),
    description: String(args.description || '').trim(),
    categoryId: args.categoryId || null,
    price: args.price != null ? Number(args.price) : null,
    originalPrice: args.originalPrice != null ? Number(args.originalPrice) : null,
    stock: Number.isFinite(args.stock) ? args.stock : 0,
    condition: args.condition || 'new',
    weightGrams: args.weightGrams || null,
    shippingRequired: args.shippingRequired !== false,
  };
  if (!data.title) return { error: 'Product title is required.' };
  if (!data.price || data.price <= 0) return { error: 'A positive price is required.' };
  const productService = require('../products/product-service');
  const product = await productService.createProduct({
    sellerProfileId: ctx.sellerProfileId,
    data,
  });
  return {
    success: true,
    product: {
      id: product.id,
      title: product.title,
      price: product.price,
      currency: product.currency,
      status: product.status,
      slug: product.slug,
    },
    note: 'Draft created. It is not published until you confirm publication.',
  };
}

async function updateProductDraftAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { error: 'No seller profile.' };
  if (!args.id) return { error: 'Product id is required.' };
  const productService = require('../products/product-service');
  const owned = await productService.getOwnedProduct({
    id: args.id,
    sellerProfileId: ctx.sellerProfileId,
    userId: ctx.userId,
  });
  if (owned.status !== 'draft') {
    return { error: 'Only draft products can be updated by the agent.' };
  }
  const patch = {};
  const allowed = ['title', 'description', 'categoryId', 'price', 'originalPrice', 'stock', 'condition', 'weightGrams', 'shippingRequired'];
  for (const key of allowed) {
    if (args[key] !== undefined) {
      if (key === 'price' || key === 'originalPrice') {
        patch[key] = args[key] != null ? BigInt(args[key]) : null;
      } else {
        patch[key] = args[key];
      }
    }
  }
  const updated = await productService.updateProduct({
    id: args.id, sellerProfileId: ctx.sellerProfileId, data: patch, userId: ctx.userId,
  });
  return { success: true, product: { id: updated.id, title: updated.title, status: updated.status } };
}

/*───────────────────────── Execute tools (approval required) ─────────────────────────*/

async function publishProductAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { error: 'No seller profile.' };
  if (!args.id) return { error: 'Product id is required.' };
  const productService = require('../products/product-service');
  const owned = await productService.getOwnedProduct({
    id: args.id,
    sellerProfileId: ctx.sellerProfileId,
    userId: ctx.userId,
  });
  if (owned.status === 'published') {
    return { error: 'Product is already published.' };
  }
  // Revalidate publication requirements server-side.
  if (!owned.title || Number(owned.price) <= 0) {
    return { error: 'Cannot publish: title and price are required.' };
  }
  const product = await productService.setStatus({
    id: args.id, sellerProfileId: ctx.sellerProfileId, status: 'published', userId: ctx.userId,
  });
  return {
    success: true,
    product: { id: product.id, title: product.title, status: product.status },
    note: 'Product is now published and visible to buyers.',
  };
}

async function archiveProductAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { error: 'No seller profile.' };
  if (!args.id) return { error: 'Product id is required.' };
  const productService = require('../products/product-service');
  const owned = await productService.getOwnedProduct({
    id: args.id,
    sellerProfileId: ctx.sellerProfileId,
    userId: ctx.userId,
  });
  const product = await productService.setStatus({
    id: args.id, sellerProfileId: ctx.sellerProfileId, status: 'archived', userId: ctx.userId,
  });
  return { success: true, product: { id: product.id, status: product.status } };
}

async function deleteProductAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { error: 'No seller profile.' };
  if (!args.id) return { error: 'Product id is required.' };
  const productService = require('../products/product-service');
  await productService.getOwnedProduct({
    id: args.id,
    sellerProfileId: ctx.sellerProfileId,
    userId: ctx.userId,
  });
  const product = await productService.softDelete({
    id: args.id, sellerProfileId: ctx.sellerProfileId, userId: ctx.userId,
  });
  return {
    success: true,
    product: { id: product.id, status: product.status },
    note: 'Product soft-deleted. It can be restored; orders referencing it are preserved.',
  };
}

async function prepareWithdrawalAgent(args, ctx) {
  if (!ctx.sellerProfileId) return { error: 'No seller profile.' };
  const amount = Number(args.amount);
  if (!Number.isFinite(amount) || amount <= 0) return { error: 'A valid positive amount is required.' };
  const phoneNumber = args.phoneNumber || null;
  // Validation happens in requestWithdrawal (balance, limits, daily cap). We only
  // prepare here; the actual funds move only after explicit approval.
  const walletService = require('../wallet/wallet-service');
  const wallet = await walletService.getWallet(ctx.sellerProfileId);
  const available = Number(wallet.availableBalance || 0);
  if (amount > available) {
    return { error: `Insufficient balance. Available: TZS ${available.toLocaleString()}.` };
  }
  const min = Number(process.env.WITHDRAWAL_MIN) || 0;
  const max = Number(process.env.WITHDRAWAL_MAX) || 5_000_000;
  if (amount < min) return { error: `Below minimum withdrawal of TZS ${min.toLocaleString()}.` };
  if (amount > max) return { error: `Above maximum withdrawal of TZS ${max.toLocaleString()}.` };
  return {
    prepared: true,
    amount,
    currency: 'TZS',
    availableBalance: available,
    netAfterFee: amount, // fee computed at execution via clickpesaPayoutPreview
    phoneNumber,
    note: 'Withdrawal prepared. It will only be sent after you confirm and pass MFA.',
  };
}

async function submitApprovedWithdrawalAgent(args, ctx) {
  // This is the MFA-gated execution path. The amount/phone must match a
  // previously approved pending action; the orchestrator enforces that.
  if (!ctx.sellerProfileId) return { error: 'No seller profile.' };
  const amount = Number(args.amount);
  const phoneNumber = args.phoneNumber || null;
  if (!Number.isFinite(amount) || amount <= 0) return { error: 'A valid positive amount is required.' };
  const walletService = require('../wallet/wallet-service');
  const result = await walletService.requestWithdrawal({
    sellerId: ctx.sellerProfileId,
    amount,
    phoneNumber,
  });
  return {
    success: true,
    withdrawal: result.withdrawal,
    wallet: result.wallet,
    note: 'Withdrawal submitted to the payment provider. Funds move only after provider confirmation.',
  };
}

async function cancelOrderAgent(args, ctx) {
  if (!ctx.userId) return { error: 'Not authenticated.' };
  if (!args.orderId) return { error: 'Order id is required.' };
  const result = await orderService.cancelOrder({
    orderId: args.orderId,
    actorId: ctx.userId,
    reason: args.reason || 'Cancelled via Soko Vibe AI agent',
  });
  return {
    success: true,
    order: { id: result.id, status: result.status, orderNumber: result.orderNumber },
    note: 'Order cancellation requested. Refunds, if any, follow the escrow rules.',
  };
}

async function confirmDeliveryAgent(args, ctx) {
  if (!ctx.userId) return { error: 'Not authenticated.' };
  if (!args.orderId) return { error: 'Order id is required.' };
  const orderService = require('../orders/order-service');
  const updated = await orderService.completeOrder({
    orderId: args.orderId,
    actorId: ctx.userId,
    method: 'OTP_VERIFY',
  });
  return {
    success: true,
    order: { id: updated.order.id, status: updated.order.status },
    note: updated.status === 'COMPLETED' ? 'Delivery confirmed and escrow released.' : updated.status,
  };
}

async function searchSupportArticlesAgent(args) {
  const query = clip(args.query, 200);
  if (!query) return { articles: [], note: 'A query is required.' };
  // Use web search for current support guidance; the agent also knows platform
  // policy from its system prompt. This is read-only guidance, not account data.
  const results = await searchWeb({ query: `Soko Vibe ${query} support help`, maxResults: 5 });
  return {
    query,
    articles: (results.results || []).map((r) => ({
      title: r.title,
      url: r.url,
      snippet: r.snippet,
    })),
    note: 'These are public support resources, not your private account data.',
  };
}

async function createSupportTicketAgent(args, ctx) {
  if (!ctx.userId) return { error: 'Not authenticated.' };
  const store = getStore();
  const ticket = await store.supportTicket.create({
    data: {
      userId: ctx.userId,
      subject: String(args.subject || 'Support request via AI agent').slice(0, 200),
      description: String(args.description || '').slice(0, 5000),
      status: 'open',
      createdAt: new Date(),
    },
  });
  return {
    success: true,
    ticket: { id: ticket.id, subject: ticket.subject, status: ticket.status },
    note: 'Support ticket created. A support agent will review it.',
  };
}

/*───────────────────────── Tool specs ─────────────────────────*/

// Read-only tools — no approval, no MFA, audit logged.
const READ_TOOLS = {
  search_products: {
    definition: {
      type: 'function',
      function: {
        name: 'search_products',
        description: 'Search products currently listed on Soko Vibe. Returns real listings with price, seller, stock and category.',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'What the user is looking for.' },
            min_price: { type: 'number', description: 'Optional minimum price in TZS.' },
            max_price: { type: 'number', description: 'Optional maximum price in TZS.' },
          },
          required: ['query'],
        },
      },
    },
    run: (args) => searchProductsAgent(args),
    category: 'product', impact: 'read', permissions: [], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  get_product_details: {
    definition: {
      type: 'function',
      function: {
        name: 'get_product_details',
        description: 'Get full details of a single Soko Vibe product by id.',
        parameters: {
          type: 'object',
          properties: { id: { type: 'string', description: 'Product id.' } },
          required: ['id'],
        },
      },
    },
    run: (args) => getProductDetailsAgent(args),
    category: 'product', impact: 'read', permissions: [], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  get_my_profile: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_profile',
        description: "Read the caller's own account: name, email, phone, KYC status, account state.",
        parameters: { type: 'object', properties: {} },
      },
    },
    run: (args, ctx) => getMyProfileAgent(args, ctx),
    category: 'account', impact: 'read', permissions: ['read_my_profile'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  get_my_orders: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_orders',
        description: "List the caller's own orders (buyer or seller) with status and totals.",
        parameters: {
          type: 'object',
          properties: {
            status: { type: 'string', enum: ['pending','paid','shipped','delivered','cancelled','disputed'], description: 'Optional status filter.' },
          },
        },
      },
    },
    run: (args, ctx) => getMyOrdersAgent(args, ctx),
    category: 'order', impact: 'read', permissions: ['read_my_orders'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  get_my_wallet_balance: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_wallet_balance',
        description: "Read the caller's own seller wallet balances (available, pending, frozen, earned, withdrawn). Read-only — no money moves.",
        parameters: { type: 'object', properties: {} },
      },
    },
    run: (args, ctx) => getMyWalletBalanceAgent(args, ctx),
    category: 'wallet', impact: 'read', permissions: ['read_my_wallet'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  get_my_transactions: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_transactions',
        description: "Read the caller's own wallet transaction ledger history.",
        parameters: { type: 'object', properties: {} },
      },
    },
    run: (args, ctx) => getMyTransactionsAgent(args, ctx),
    category: 'wallet', impact: 'read', permissions: ['read_my_wallet'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  get_my_notifications: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_notifications',
        description: "Read the caller's own recent notifications.",
        parameters: { type: 'object', properties: {} },
      },
    },
    run: (args, ctx) => getMyNotificationsAgent(args, ctx),
    category: 'notification', impact: 'read', permissions: ['read_my_notifications'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  search_support_articles: {
    definition: {
      type: 'function',
      function: {
        name: 'search_support_articles',
        description: 'Search public Soko Vibe support guidance. Read-only guidance, not account data.',
        parameters: {
          type: 'object',
          properties: { query: { type: 'string', description: 'Support topic to look up.' } },
          required: ['query'],
        },
      },
    },
    run: (args) => searchSupportArticlesAgent(args),
    category: 'support', impact: 'read', permissions: [], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
};

// Prepare tools — create drafts; require approval only at final mutation.
const PREPARE_TOOLS = {
  create_product_draft: {
    definition: {
      type: 'function',
      function: {
        name: 'create_product_draft',
        description: 'Create a draft product listing (not yet published). The user must confirm before it goes live.',
        parameters: {
          type: 'object',
          properties: {
            title: { type: 'string', description: 'Product title (min 3 chars).' },
            description: { type: 'string', description: 'Product description.' },
            categoryId: { type: 'string', description: 'Category id (uuid).' },
            price: { type: 'number', description: 'Price in TZS (positive integer).' },
            originalPrice: { type: 'number', description: 'Original price in TZS.' },
            stock: { type: 'number', description: 'Stock quantity (integer >= 0).' },
            condition: { type: 'string', description: 'Condition: new, used, refurbished.' },
            weightGrams: { type: 'number', description: 'Weight in grams.' },
            shippingRequired: { type: 'boolean', description: 'Whether shipping is required.' },
          },
          required: ['title', 'price'],
        },
      },
    },
    run: (args, ctx) => createProductDraftAgent(args, ctx),
    category: 'product', impact: 'prepare', permissions: ['prepare_product_drafts'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  update_product_draft: {
    definition: {
      type: 'function',
      function: {
        name: 'update_product_draft',
        description: 'Update a draft product the caller owns. Cannot publish or change a published listing.',
        parameters: {
          type: 'object',
          properties: {
            id: { type: 'string', description: 'Draft product id.' },
            title: { type: 'string' },
            description: { type: 'string' },
            categoryId: { type: 'string' },
            price: { type: 'number' },
            originalPrice: { type: 'number' },
            stock: { type: 'number' },
            condition: { type: 'string' },
            weightGrams: { type: 'number' },
            shippingRequired: { type: 'boolean' },
          },
          required: ['id'],
        },
      },
    },
    run: (args, ctx) => updateProductDraftAgent(args, ctx),
    category: 'product', impact: 'prepare', permissions: ['prepare_product_drafts'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
  prepare_withdrawal: {
    definition: {
      type: 'function',
      function: {
        name: 'prepare_withdrawal',
        description: 'Prepare a withdrawal for review: checks balance and limits, but no money moves until confirmed.',
        parameters: {
          type: 'object',
          properties: {
            amount: { type: 'number', description: 'Withdrawal amount in TZS (positive integer).' },
            phoneNumber: { type: 'string', description: 'Payout phone number (optional; uses profile phone if omitted).' },
          },
          required: ['amount'],
        },
      },
    },
    run: (args, ctx) => prepareWithdrawalAgent(args, ctx),
    category: 'wallet', impact: 'prepare', permissions: ['prepare_withdrawal'], requiresApproval: false,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
};

// Execute tools — require explicit approval + MFA before execution.
const EXECUTE_TOOLS = {
  publish_product: {
    definition: {
      type: 'function',
      function: {
        name: 'publish_product',
        description: 'Publish a draft product the caller owns, making it visible to buyers. Requires explicit confirmation.',
        parameters: {
          type: 'object',
          properties: { id: { type: 'string', description: 'Draft product id to publish.' } },
          required: ['id'],
        },
      },
    },
    run: (args, ctx) => publishProductAgent(args, ctx),
    category: 'product', impact: 'execute', permissions: ['publish_products'], requiresApproval: true,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: false, audit: true,
  },
  archive_product: {
    definition: {
      type: 'function',
      function: {
        name: 'archive_product',
        description: 'Archive a product the caller owns (unpublish, keep record). Requires explicit confirmation.',
        parameters: {
          type: 'object',
          properties: { id: { type: 'string', description: 'Product id to archive.' } },
          required: ['id'],
        },
      },
    },
    run: (args, ctx) => archiveProductAgent(args, ctx),
    category: 'product', impact: 'execute', permissions: ['publish_products'], requiresApproval: true,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: false, audit: true,
  },
  delete_product: {
    definition: {
      type: 'function',
      function: {
        name: 'delete_product',
        description: 'Soft-delete a product the caller owns. Destructive — requires explicit confirmation.',
        parameters: {
          type: 'object',
          properties: { id: { type: 'string', description: 'Product id to delete.' } },
          required: ['id'],
        },
      },
    },
    run: (args, ctx) => deleteProductAgent(args, ctx),
    category: 'product', impact: 'destructive', permissions: ['delete_products'], requiresApproval: true,
    requiresMfa: true, timeoutMs: TOOL_TIMEOUT_MS, retryable: false, audit: true,
  },
  submit_withdrawal: {
    definition: {
      type: 'function',
      function: {
        name: 'submit_withdrawal',
        description: 'Submit a prepared withdrawal to the payment provider. Money moves — requires explicit confirmation and MFA.',
        parameters: {
          type: 'object',
          properties: {
            amount: { type: 'number', description: 'Withdrawal amount in TZS (must match the approved preparation).' },
            phoneNumber: { type: 'string', description: 'Payout phone number.' },
          },
          required: ['amount'],
        },
      },
    },
    run: (args, ctx) => submitApprovedWithdrawalAgent(args, ctx),
    category: 'wallet', impact: 'financial', permissions: ['execute_withdrawal'], requiresApproval: true,
    requiresMfa: true, timeoutMs: WITHDRAWAL_TIMEOUT_MS, retryable: false, audit: true,
  },
  cancel_order: {
    definition: {
      type: 'function',
      function: {
        name: 'cancel_order',
        description: "Request cancellation of the caller's own order. Refund rules apply. Requires explicit confirmation.",
        parameters: {
          type: 'object',
          properties: {
            orderId: { type: 'string', description: 'Order id to cancel.' },
            reason: { type: 'string', description: 'Optional cancellation reason.' },
          },
          required: ['orderId'],
        },
      },
    },
    run: (args, ctx) => cancelOrderAgent(args, ctx),
    category: 'order', impact: 'execute', permissions: ['manage_my_orders'], requiresApproval: true,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: false, audit: true,
  },
  confirm_delivery: {
    definition: {
      type: 'function',
      function: {
        name: 'confirm_delivery',
        description: "Confirm delivery of the caller's own order, releasing escrow to the seller. Financially consequential — requires explicit confirmation.",
        parameters: {
          type: 'object',
          properties: { orderId: { type: 'string', description: 'Order id to confirm delivery for.' } },
          required: ['orderId'],
        },
      },
    },
    run: (args, ctx) => confirmDeliveryAgent(args, ctx),
    category: 'order', impact: 'financial', permissions: ['manage_my_orders'], requiresApproval: true,
    requiresMfa: true, timeoutMs: TOOL_TIMEOUT_MS, retryable: false, audit: true,
  },
  create_support_ticket: {
    definition: {
      type: 'function',
      function: {
        name: 'create_support_ticket',
        description: 'Create a support ticket for the caller. Requires explicit confirmation.',
        parameters: {
          type: 'object',
          properties: {
            subject: { type: 'string', description: 'Ticket subject.' },
            description: { type: 'string', description: 'Ticket description.' },
          },
          required: ['subject', 'description'],
        },
      },
    },
    run: (args, ctx) => createSupportTicketAgent(args, ctx),
    category: 'support', impact: 'execute', permissions: ['create_support_tickets'], requiresApproval: true,
    requiresMfa: false, timeoutMs: TOOL_TIMEOUT_MS, retryable: true, audit: true,
  },
};

const TOOLS = { ...READ_TOOLS, ...PREPARE_TOOLS, ...EXECUTE_TOOLS };

function definitions() {
  return Object.values(TOOLS).map((t) => t.definition);
}

function get(name) {
  return TOOLS[name];
}

async function invoke(name, rawArgs, ctx) {
  const tool = TOOLS[name];
  if (!tool) return { error: `No such agent tool: ${clip(name, 60)}` };
  let args = {};
  try {
    args = rawArgs && typeof rawArgs === 'object' ? rawArgs : JSON.parse(rawArgs || '{}');
  } catch {
    return { error: 'Tool arguments were not valid JSON' };
  }
  try {
    return await tool.run(args, ctx);
  } catch (e) {
    console.error(`[agent] tool ${name} failed:`, e.message);
    return { error: `${name} could not be completed: ${e.message || 'unknown error' }` };
  }
}

module.exports = { definitions, get, invoke, TOOLS, READ_TOOLS, PREPARE_TOOLS, EXECUTE_TOOLS };
