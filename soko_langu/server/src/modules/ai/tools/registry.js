const { getStore } = require('../../../config/database');
const searchService = require('../../search/search-service');
const { searchWeb } = require('../tavily');

// A tool is { definition, run }.
//
// The split matters for safety. `definition` is the only part the model ever
// sees, so the model can choose a tool and pass arguments but can never point
// at a collection, a document id, or a user. `run` receives those from ctx,
// which routes.js fills from the verified Firebase token. There is deliberately
// no tool argument that accepts a uid: a model that hallucinates one has
// nothing to put it in.
//
// Every run() must return JSON-serialisable data and must not throw; a tool
// failure becomes a tool result the model can reason about, because an
// exception here would abort the whole request.

const MAX_PRODUCTS = 6;
const MAX_ORDERS = 5;

function clip(value, max) {
  const s = typeof value === 'string' ? value : String(value ?? '');
  return s.length > max ? s.slice(0, max) + '…' : s;
}

/** Products currently listed on Soko Vibe. Public: no uid needed. */
async function searchProducts(args) {
  const query = clip(args.query, 120);
  if (!query) return { products: [], note: 'A query is required.' };

  const minPrice = Number.isFinite(args.min_price) ? args.min_price : undefined;
  const maxPrice = Number.isFinite(args.max_price) ? args.max_price : undefined;

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

/** Orders belonging to the caller, as buyer or seller. ctx.userId only. */
async function getMyOrders(args, ctx) {
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
      status: o.status ?? null,
      total: o.total ?? o.totalAmount ?? null,
      currency: o.currency ?? 'TZS',
      created_at: o.createdAt ?? null,
      // Never echo the other party's contact details into the model's context.
      role: o.buyerId === ctx.userId ? 'buyer' : 'seller',
    })),
  };
}

/**
 * Account and verification status for the caller.
 *
 * Only fields that are safe to show back to the owner are read, and money is
 * deliberately excluded: wallet/balances live outside the assistant, so the
 * model can neither quote nor act on money state. isAdmin and session fields
 * are also not exposed: the model does not need them and a tool response is a
 * poor place to carry privilege.
 */
async function getMyProfile(args, ctx) {
  if (!ctx.userId) return { note: 'No user record for this token.' };
  const store = getStore();
  const u = await store.user.findUnique({
    where: { id: ctx.userId },
    select: {
      displayName: true, email: true, phone: true, role: true,
      accountStatus: true, kycStatus: true, kycVerified: true,
      createdAt: true,
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

// The only sellerProfile columns the assistant may write. Anything financial —
// wallet, withdrawals, revenue, totals, payout settings, escrow — is not here
// and never will be: the money system has no agent access.
const SELLER_EDITABLE_FIELDS = ['storeName', 'storeDescription', 'logoUrl', 'coverUrl', 'businessType'];
const SELLER_FIELD_CAPS = { storeName: 100, storeDescription: 2000, logoUrl: 500, coverUrl: 500, businessType: 50 };

// Edits the caller's own store profile by command, mirroring what the regular
// PUT /sellers/profile endpoint accepts. The profile is resolved from ctx (the
// verified token), never from an argument, so a hallucinated id has nowhere to
// land. Unknown keys are ignored, including any money key the model invents.
async function updateMyStore(args, ctx) {
  if (!ctx.sellerProfileId) {
    return { error: 'No seller profile for this account. Become a seller first.' };
  }

  const data = {};
  for (const field of SELLER_EDITABLE_FIELDS) {
    const raw = args[field];
    if (raw == null) continue;
    let value = String(raw).trim();
    const cap = SELLER_FIELD_CAPS[field];
    if (value.length > cap) value = value.slice(0, cap);
    if (field === 'storeName' && !value) return { error: 'storeName cannot be empty.' };
    data[field] = value;
  }
  if (!Object.keys(data).length) {
    return {
      error: 'Tell the seller which field to change: storeName, storeDescription, businessType, logoUrl or coverUrl.',
    };
  }

  const store = getStore();
  try {
    await store.sellerProfile.update({ where: { id: ctx.sellerProfileId }, data });
  } catch (e) {
    console.error('[ai] update_my_store failed:', e.message);
    return { error: 'Store update could not be saved. Ask the seller to retry or contact support.' };
  }

  return {
    success: true,
    updated: data,
    note: 'Store details only. Money, wallet, balances and payments are never changed by the assistant.',
  };
}

const TOOLS = {
  search_products: {
    definition: {
      type: 'function',
      function: {
        name: 'search_products',
        description:
          'Search products currently listed on Soko Vibe. Use this before claiming a price or availability. Returns real listings only.',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'What the user is looking for, in their own words.' },
            min_price: { type: 'number', description: 'Optional minimum price in TZS.' },
            max_price: { type: 'number', description: 'Optional maximum price in TZS.' },
          },
          required: ['query'],
        },
      },
    },
    run: (args) => searchProducts(args),
  },
  get_my_orders: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_orders',
        description:
          "List the caller's own orders, where they are the buyer or the seller. Use this for 'where is my order' style questions.",
        parameters: {
          type: 'object',
          properties: {
            status: {
              type: 'string',
              enum: ['pending', 'paid', 'shipped', 'delivered', 'cancelled', 'disputed'],
              description: 'Optional status filter.',
            },
          },
        },
      },
    },
    run: (args, ctx) => getMyOrders(args, ctx),
  },
  get_my_profile: {
    definition: {
      type: 'function',
      function: {
        name: 'get_my_profile',
        description:
          "Read the caller's own account: name, KYC verification status and account state. Use for 'is my KYC done' or 'how do I open a shop'. The assistant cannot read or change balances — those live outside it.",
        parameters: { type: 'object', properties: {} },
      },
    },
    run: (args, ctx) => getMyProfile(args, ctx),
  },
  update_my_store: {
    definition: {
      type: 'function',
      function: {
        name: 'update_my_store',
        description:
          "Update the caller's OWN store profile only (storeName, storeDescription, businessType, logoUrl, coverUrl). The seller must explicitly ask to change something and tell you the new value. Confirm with them before writing. This tool NEVER touches money, prices, wallet, balances, payments, escrow or withdrawal settings.",
        parameters: {
          type: 'object',
          properties: {
            storeName: { type: 'string', description: 'New store name (max 100 chars).' },
            storeDescription: { type: 'string', description: 'New store description (max 2000 chars).' },
            businessType: { type: 'string', description: 'Business type, e.g. electronics, fashion (max 50 chars).' },
            logoUrl: { type: 'string', description: 'New logo image URL.' },
            coverUrl: { type: 'string', description: 'New cover image URL.' },
          },
        },
      },
    },
    run: (args, ctx) => updateMyStore(args, ctx),
  },
  search_web: {
    definition: {
      type: 'function',
      function: {
        name: 'search_web',
        description:
          'Search the public internet for current information and get back source URLs. You MUST use this for anything not on Soko Vibe: exchange rates, laws, sports, weather, prices outside the app, company details, and any fact that could have changed. Never answer those from memory.',
        parameters: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'A specific search query. Include the subject and anything time-sensitive.' },
            max_results: { type: 'number', description: 'Optional, 1-5.' },
          },
          required: ['query'],
        },
      },
    },
    run: (args) => searchWeb({ query: args.query, maxResults: args.max_results }),
  },
};

/** Definitions in the shape the OpenAI-compatible API expects. */
function definitions() {
  return Object.values(TOOLS).map((t) => t.definition);
}

/**
 * Runs one tool call. Never throws: the model has to be able to read the
 * failure and either retry differently or tell the user, rather than the whole
 * request collapsing.
 */
async function invoke(name, rawArgs, ctx) {
  const tool = TOOLS[name];
  if (!tool) {
    return { error: `No such tool: ${clip(name, 60)}` };
  }
  let args = {};
  try {
    args = rawArgs && typeof rawArgs === 'object' ? rawArgs : JSON.parse(rawArgs || '{}');
  } catch {
    return { error: 'Tool arguments were not valid JSON' };
  }
  try {
    return await tool.run(args, ctx);
  } catch (e) {
    console.error(`[ai] tool ${name} failed:`, e.message);
    return { error: `${name} could not be completed` };
  }
}

module.exports = { definitions, invoke, TOOLS };
