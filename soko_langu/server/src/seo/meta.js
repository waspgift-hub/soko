'use strict';

const { getFirebaseFirestore } = require('../config/firebase');

const SITE = {
  name: 'Soko Vibe',
  canonicalHost: 'https://www.sokovibe.co.tz',
  homeTitle: "Soko Vibe | Tanzania's Trusted Online Marketplace",
  homeDescription:
    'Soko Vibe ni marketplace ya Tanzania. Nunua na uze bidhaa new na second-hand kwa escrow-protected payment, real-time chat, voice search na delivery nchi nzima.',
  logo: 'https://www.sokovibe.co.tz/icons/Icon-512.png',
};

const PRIVATE_PREFIXES = [
  '/login',
  '/register',
  '/forgot-password',
  '/verify-email',
  '/account-selection',
  '/chats',
  '/chat',
  '/cart',
  '/checkout',
  '/profile',
  '/settings',
  '/edit-profile',
  '/my-ads',
  '/wishlist',
  '/shop-customize',
  '/add-product',
  '/notifications',
  '/notification-preferences',
  '/seller',
  '/seller-earnings',
  '/seller-analytics',
  '/seller-dispatch',
  '/seller-orders',
  '/seller-quote',
  '/kyc',
  '/report',
  '/admin',
  '/product-boost',
  '/boost-receipt',
  '/my-purchases',
  '/receipt',
  '/order-detail',
  '/order-flow',
  '/create-group',
  '/group-chat',
  '/create-flash-sale',
  '/product-reviews',
  '/post-buyer-request',
  '/buyer-requests',
  '/follow-list',
  '/ai-assistant',
];

const PUBLIC_STATIC_TITLES = {
  '/search': 'Tafuta Bidhaa | Soko Vibe Tanzania',
  '/category': 'Categories | Soko Vibe Tanzania',
  '/discovery': 'Discover | Soko Vibe Tanzania',
  '/flash-sale': 'Flash Sale | Soko Vibe Tanzania',
  '/help': 'Help Center | Soko Vibe',
  '/about': 'About Soko Vibe | Tanzania Online Marketplace',
  '/privacy-policy': 'Privacy Policy | Soko Vibe',
  '/terms-of-service': 'Terms of Service | Soko Vibe',
};

function canonicalUrl(req) {
  const pathname = req.path && req.path !== '/' ? req.path : '/';
  return `${SITE.canonicalHost}${pathname}`;
}

function classify(pathname) {
  if (pathname === '/') return 'home';
  if (pathname.startsWith('/product/')) return 'product';
  if (pathname.startsWith('/category-products/')) return 'category';
  if (pathname.startsWith('/public-profile/')) return 'publicProfile';
  if (Object.prototype.hasOwnProperty.call(PUBLIC_STATIC_TITLES, pathname)) return 'publicStatic';
  if (PRIVATE_PREFIXES.some((p) => pathname === p || pathname.startsWith(`${p}/`))) return 'private';
  return 'unknown';
}

function truncate(text, max) {
  const clean = String(text || '').replace(/\s+/g, ' ').trim();
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}

function esc(text) {
  return String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function jsonLd(blocks) {
  return blocks
    .filter(Boolean)
    .map((b) => `<script type="application/ld+json">${JSON.stringify(b)}</script>`)
    .join('\n');
}

function websiteSchema() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: SITE.name,
    alternateName: 'SV',
    url: `${SITE.canonicalHost}/`,
  };
}

function organizationSchema() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: SITE.name,
    url: `${SITE.canonicalHost}/`,
    logo: SITE.logo,
  };
}

async function fetchProductSnapshot(id) {
  const db = getFirebaseFirestore();
  if (!db) return { exists: null };
  try {
    const snap = await db.collection('products').doc(id).get();
    if (!snap.exists) return { exists: false };
    return { exists: true, data: snap.data() || {} };
  } catch (error) {
    console.error('[SEO] product lookup failed:', error.message);
    return { exists: null };
  }
}

async function buildMeta(req) {
  const type = classify(req.path);
  const base = { robots: 'index, follow', ogType: 'website', ogImage: SITE.logo, jsonLd: [] };

  if (type === 'product') {
    const id = decodeURIComponent(req.path.split('/')[2] || '');
    const snap = await fetchProductSnapshot(id);
    if (snap.exists === false) return { status: 404 };
    if (snap.exists === null) {
      // Firestore unavailable — serve the SPA shell so the app can render.
      return { status: 200, ...base, title: `${SITE.name} | Product`, description: SITE.homeDescription, canonical: canonicalUrl(req) };
    }
    const d = snap.data;
    const name = d.name || id;
    const title = `${name} | Soko Vibe Tanzania`;
    const description = truncate(d.description || `Nunua ${name} kwa bei nzuri kwenye Soko Vibe Tanzania.`, 158);
    const image = Array.isArray(d.images) && d.images[0] ? d.images[0] : SITE.logo;
    const robots = d.isActive === false ? 'noindex, nofollow' : 'index, follow';
    const url = `${SITE.canonicalHost}/product/${encodeURIComponent(id)}`;
    const productSchema = {
      '@context': 'https://schema.org',
      '@type': 'Product',
      name,
      image: [image],
      description: truncate(d.description || description, 400),
      brand: d.brand ? { '@type': 'Brand', name: String(d.brand).slice(0, 100) } : undefined,
      offers: {
        '@type': 'Offer',
        url,
        priceCurrency: d.currency || 'TZS',
        price: String(d.price ?? 0),
        availability: d.isActive === false
          ? 'https://schema.org/OutOfStock'
          : 'https://schema.org/InStock',
      },
    };
    return {
      status: 200,
      robots,
      title,
      description,
      canonical: url,
      ogType: 'product',
      ogImage: image,
      jsonLd: [productSchema, websiteSchema()],
    };
  }

  if (type === 'category') {
    const name = decodeURIComponent(req.path.split('/')[2] || '');
    const display = name.replace(/-/g, ' ');
    return {
      status: 200,
      ...base,
      robots: 'index, follow',
      title: `Nunua ${display[0].toUpperCase() + display.slice(1)} | Soko Vibe Tanzania`,
      description: `Nunua na / au uze bidhaa za ${display} kwenye Soko Vibe Tanzania.`,
      canonical: canonicalUrl(req),
      ogImage: SITE.logo,
      jsonLd: [
        {
          '@context': 'https://schema.org',
          '@type': 'BreadcrumbList',
          itemListElement: [
            { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE.canonicalHost}/` },
            { '@type': 'ListItem', position: 2, name: display, item: `${SITE.canonicalHost}${req.path}` },
          ],
        },
        websiteSchema(),
      ],
    };
  }

  if (type === 'publicProfile') {
    const uid = decodeURIComponent(req.path.split('/')[2] || '');
    const db = getFirebaseFirestore();
    let handle = uid;
    if (db) {
      try {
        const snap = await db.collection('users').doc(uid).get();
        if (snap.exists && snap.data().username) handle = snap.data().username;
      } catch (error) {
        console.error('[SEO] user lookup failed:', error.message);
      }
    }
    return {
      status: 200,
      ...base,
      robots: 'index, follow',
      title: `${handle} | Soko Vibe Tanzania`,
      description: `Duka la ${handle} kwenye Soko Vibe Tanzania — nunua kutoka kwa muuzaji aliye na mabidhaa halisi.`,
      canonical: canonicalUrl(req),
    };
  }

  if (type === 'home') {
    return {
      status: 200,
      ...base,
      robots: 'index, follow',
      title: SITE.homeTitle,
      description: SITE.homeDescription,
      canonical: `${SITE.canonicalHost}/`,
      ogType: 'website',
      ogImage: SITE.logo,
      jsonLd: [websiteSchema(), organizationSchema()],
    };
  }

  if (type === 'publicStatic') {
    return {
      status: 200,
      ...base,
      robots: 'index, follow',
      title: PUBLIC_STATIC_TITLES[req.path],
      description: SITE.homeDescription,
      canonical: canonicalUrl(req),
      jsonLd: [websiteSchema()],
    };
  }

  // True 404s for bogus top-level paths (avoids soft-404s for crawlers).
  if (type === 'unknown' && req.path.indexOf('/', 1) === -1) {
    return { status: 404 };
  }

  // private or unknown-but-existing SPA routes
  return {
    status: 200,
    robots: 'noindex, nofollow',
    title: SITE.homeTitle,
    description: SITE.homeDescription,
    canonical: canonicalUrl(req),
    ogType: 'website',
    ogImage: SITE.logo,
    jsonLd: [],
  };
}

function injectMeta(html, meta) {
  const title = esc(meta.title);
  const description = esc(meta.description);
  const canonical = esc(meta.canonical);
  html = html.replace(/<title>[^<]*<\/title>/, `<title>${title}</title>`);
  html = html.replace(
    /<meta\s+name="description"\s+content="[^"]*"\s*\/?>/i,
    `<meta name="description" content="${description}">`
  );
  const head = [
    `<link rel="canonical" href="${canonical}">`,
    `<meta name="robots" content="${esc(meta.robots)}">`,
    `<meta property="og:type" content="${esc(meta.ogType)}">`,
    `<meta property="og:site_name" content="${SITE.name}">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${description}">`,
    `<meta property="og:url" content="${canonical}">`,
    '<meta name="twitter:card" content="summary_large_image">',
    `<meta name="twitter:title" content="${title}">`,
    `<meta name="twitter:description" content="${description}">`,
  ];
  if (meta.ogImage) {
    head.push(`<meta property="og:image" content="${esc(meta.ogImage)}">`);
    head.push(`<meta name="twitter:image" content="${esc(meta.ogImage)}">`);
  }
  if (Array.isArray(meta.jsonLd) && meta.jsonLd.length) {
    head.push(jsonLd(meta.jsonLd));
  }
  return html.replace('</head>', `${head.join('\n')}\n</head>`);
}

module.exports = {
  SITE,
  classify,
  buildMeta,
  injectMeta,
  canonicalUrl,
};