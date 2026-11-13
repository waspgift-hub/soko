#!/usr/bin/env node
/**
 * Soko Vibe — Category Artwork Pack pipeline.
 *
 *   node tools/category-artwork/build-pack.mjs [options]
 *
 * Takes licensed source photos, optimises them for the mobile category UI,
 * writes a versioned pack + manifest + attribution record, and (optionally)
 * uploads it to R2.
 *
 * The manifest is the contract with the app: `artwork_manifest.dart` parses and
 * validates it, so every field written here must satisfy those rules (lowercase
 * hex sha256, safe relative paths, declared byte sizes, unique ids).
 *
 * Steps
 *   1. read taxonomy            -> ids, subcategory ids, current image paths
 *   2. resolve sources          -> SOURCES.json / existing bundled assets
 *   3. optimise                 -> webp, capped dimensions, quality per role
 *   4. verify licences          -> refuse anything without a recorded licence
 *   5. emit                     -> pack dir, manifest.json, ATTRIBUTION.md
 *   6. upload                   -> R2 under artwork/<version>/ (optional)
 */

import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const TAXONOMY_FILE = path.join(REPO_ROOT, 'lib', 'data', 'marketplace_taxonomy.dart');
const SOURCES_FILE = path.join(REPO_ROOT, 'tools', 'category-artwork', 'sources', 'SOURCES.json');
const OUT_ROOT = path.join(REPO_ROOT, 'build', 'category-artwork');

// ---------------------------------------------------------------------------
// Output budgets.
//
// Sized to how each image is actually painted, not to a single global size.
// A 56x56 rail tile and a full-width 148px-tall banner do not need the same
// pixels, and shipping the banner size for both is how a "small" pack quietly
// becomes 40 MB.
// ---------------------------------------------------------------------------
const ROLES = {
  // Full-bleed card in the category grid / popular rail (~400px decode).
  category: { width: 720, height: 540, quality: 74 },
  // Filter-rail subcategory tile: rendered at 56x56 logical, 112px decode.
  subcategory: { width: 224, height: 224, quality: 70 },
};

// Identifies this pack format. The app refuses a manifest with any other value.
const PACK_NAME = 'category_artwork';

function parseArgs(argv) {
  const args = {
    version: null,
    minAppVersion: '1.0.0',
    out: OUT_ROOT,
    upload: false,
    dryRun: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--version') args.version = Number(argv[++i]);
    else if (a === '--min-app-version') args.minAppVersion = argv[++i];
    else if (a === '--out') args.out = path.resolve(argv[++i]);
    else if (a === '--upload') args.upload = true;
    else if (a === '--dry-run') args.dryRun = true;
    else throw new Error(`Unknown flag: ${a}`);
  }
  return args;
}

// ---------------------------------------------------------------------------
// Taxonomy
// ---------------------------------------------------------------------------

/**
 * Reads ids straight out of marketplace_taxonomy.dart.
 *
 * The taxonomy is the single source of truth and is `const`, so it cannot be
 * imported by a Node script. Rather than maintain a second copy (the mistake
 * that already left `master_categories.dart` dead and id-incompatible), this
 * parses the declarations.
 */
async function readTaxonomy() {
  const src = await readFile(TAXONOMY_FILE, 'utf8');
  const blocks = src.split('TaxonomyCategory(').slice(1);
  const categories = [];

  for (const block of blocks) {
    const id = block.match(/^\s*\n\s*id: '([^']+)'/)?.[1];
    if (!id) continue;

    // `order:` is optional in the constructor; absence means "not set".
    const order = block.match(/^\s*\n\s*order: (\d+)/m)?.[1];

    const subs = [...block.matchAll(/TaxonomySub\(\s*'([^']+)'\s*,\s*'([^']*)'/g)].map(
      (m) => ({ id: m[1], name: m[2] }),
    );

    categories.push({ id, order: order ? Number(order) : null, subs });
  }

  categories.sort((a, b) => (a.order ?? Infinity) - (b.order ?? Infinity));

  const seen = new Map();
  for (const c of categories) {
    for (const s of c.subs) {
      if (!seen.has(s.id)) seen.set(s.id, []);
      seen.get(s.id).push(c.id);
    }
  }
  const ambiguous = [...seen.entries()]
    .filter(([, owners]) => owners.length > 1)
    .map(([id, owners]) => ({ id, owners }));

  return { categories, ambiguous };
}

// ---------------------------------------------------------------------------
// Sources + licensing
// ---------------------------------------------------------------------------

/**
 * Permissive enough for a shipped commercial app and for redistribution inside
 * a downloadable pack. `by-sa` is deliberately excluded: it would force the
 * pack's own derivative images under the same licence and require attribution
 * inside the artwork itself.
 */
const ALLOWED_LICENSES = new Set(['cc0', 'pdm', 'publicdomain']);

const LICENSE_ALIASES = {
  'cc0': 'cc0',
  'cc0-1.0': 'cc0',
  'pdm': 'pdm',
  'public domain': 'publicdomain',
  'publicdomain': 'publicdomain',
};

/**
 * Resolves a source `file` to an absolute path.
 *
 * Paths in SOURCES.json may be repo-relative (`assets/images/...`, for art
 * already in the app) or relative to the sources directory (for newly fetched
 * files). Both forms are common, so resolve repo-relative against the repo root
 * and anything else against the sources dir.
 */
function resolveSourcePath(file) {
  const repoRelative = path.resolve(REPO_ROOT, file);
  if (existsSync(repoRelative)) return repoRelative;
  return path.resolve(path.dirname(SOURCES_FILE), file);
}

async function readSources() {
  if (!existsSync(SOURCES_FILE)) {
    throw new Error(
      `Missing ${SOURCES_FILE}. Each source needs id/type/file/license/attribution ` +
        `before a pack can be built.`,
    );
  }
  const raw = JSON.parse(await readFile(SOURCES_FILE, 'utf8'));
  if (!Array.isArray(raw.sources)) {
    throw new Error('SOURCES.json must contain a "sources" array');
  }
  return raw.sources;
}

function validateSource(source) {
  const problems = [];
  if (!source.id) problems.push('missing id');
  if (source.type !== 'category' && source.type !== 'subcategory') {
    problems.push(`type must be category|subcategory (got ${source.type})`);
  }
  if (source.type === 'subcategory' && !source.categoryId) {
    problems.push('subcategory needs categoryId');
  }
  if (!source.file) problems.push('missing file');
  if (!source.sourceUrl) problems.push('missing sourceUrl');
  if (!source.sourceSite) problems.push('missing sourceSite');

  const license = LICENSE_ALIASES[String(source.license ?? '').toLowerCase().trim()];
  if (!license) {
    problems.push(
      `license "${source.license}" is not recognised`,
    );
  } else if (!ALLOWED_LICENSES.has(license)) {
    problems.push(
      `license "${source.license}" is not in the allowed set (${[...ALLOWED_LICENSES].join(', ')})`,
    );
  }

  if (problems.length) {
    throw new Error(`Source "${source.id ?? '<no id>'}": ${problems.join('; ')}`);
  }
  return license;
}

// ---------------------------------------------------------------------------
// Optimisation
// ---------------------------------------------------------------------------

async function optimize(sourcePath, role, outFile) {
  const spec = ROLES[role];
  await mkdir(path.dirname(outFile), { recursive: true });

  const image = sharp(sourcePath, { failOn: 'none' }).rotate(); // honour EXIF
  const meta = await image.metadata();

  const buf = await image
    .resize({
      width: spec.width,
      height: spec.height,
      fit: 'inside',
      withoutEnlargement: true,
    })
    .webp({ quality: spec.quality, effort: 5 })
    .toBuffer();

  await writeFile(outFile, buf);
  const outMeta = await sharp(buf).metadata();
  // sharp's `metadata().size` is undefined when reading from a path, so the
  // source size comes from the filesystem — it drives the compression report.
  const originalSize = (await stat(sourcePath)).size;

  return {
    size: buf.length,
    sha256: createHash('sha256').update(buf).digest('hex'),
    width: outMeta.width ?? 0,
    height: outMeta.height ?? 0,
    originalSize,
    originalWidth: meta.width ?? 0,
    originalHeight: meta.height ?? 0,
  };
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

async function build(args) {
  const started = Date.now();
  const { categories, ambiguous } = await readTaxonomy();

  if (ambiguous.length) {
    // Subcategory ids are keys in the manifest, so a slug used by two
    // categories would collide. Surfaced rather than silently suffixed.
    console.warn(
      `[taxonomy] ${ambiguous.length} subcategory id(s) shared across categories:`,
    );
    for (const a of ambiguous) {
      console.warn(`  ${a.id}: ${a.owners.join(', ')}`);
    }
  }

  const sources = await readSources();
  const sourceByKey = new Map();
  for (const s of sources) {
    const license = validateSource(s);
    const key = s.type === 'category' ? `category:${s.id}` : `sub:${s.categoryId}/${s.id}`;
    if (sourceByKey.has(key)) {
      throw new Error(`Duplicate source for ${key}`);
    }
    sourceByKey.set(key, { ...s, license });
  }

  const categoryIds = new Set(categories.map((c) => c.id));
  const subIds = new Set();
  for (const c of categories) for (const s of c.subs) subIds.add(`${c.id}/${s.id}`);

  // Warn on drift in both directions so a taxonomy edit without a matching
  // artwork source is visible in CI instead of shipping as a silent icon.
  for (const key of sourceByKey.keys()) {
    const [type, id] = key.split(/:(.+)/);
    if (type === 'category' && !categoryIds.has(id)) {
      console.warn(`[drift] artwork source for unknown category "${id}"`);
    }
    if (type === 'sub' && !subIds.has(id)) {
      console.warn(`[drift] artwork source for unknown subcategory "${id}"`);
    }
  }
  for (const id of categoryIds) {
    if (!sourceByKey.has(`category:${id}`)) {
      console.warn(`[missing] no artwork source for category "${id}"`);
    }
  }

  const version =
    args.version ?? (await nextVersion(args.out));
  const outDir = path.join(args.out, String(version));

  if (existsSync(outDir) && !args.dryRun) {
    await rm(outDir, { recursive: true, force: true });
  }
  await mkdir(outDir, { recursive: true });

  const assets = [];
  const attribution = [];

  for (const cat of categories) {
    // --- category artwork ---
    const catSource = sourceByKey.get(`category:${cat.id}`);
    if (catSource) {
      const file = `categories/${cat.id}.webp`;
      const abs = resolveSourcePath(catSource.file);
      const info = await optimize(abs, 'category', path.join(outDir, file));
      assets.push({
        id: cat.id,
        type: 'category',
        file,
        sha256: info.sha256,
        size: info.size,
        width: info.width,
        height: info.height,
      });
      attribution.push({ ...catSource, out: file, ...info });
    }

    // --- subcategory artwork ---
    for (const sub of cat.subs) {
      const subSource = sourceByKey.get(`sub:${cat.id}/${sub.id}`);
      if (!subSource) continue;
      const file = `subcategories/${cat.id}/${sub.id}.webp`;
      const abs = resolveSourcePath(subSource.file);
      const info = await optimize(abs, 'subcategory', path.join(outDir, file));
      assets.push({
        id: `${cat.id}/${sub.id}`,
        type: 'subcategory',
        categoryId: cat.id,
        file,
        sha256: info.sha256,
        size: info.size,
        width: info.width,
        height: info.height,
      });
      attribution.push({ ...subSource, out: file, ...info });
    }
  }

  if (assets.length === 0) {
    throw new Error('No artwork produced — refusing to publish an empty pack');
  }

  const totalBytes = assets.reduce((sum, a) => sum + a.size, 0);
  const originalBytes = attribution.reduce((sum, a) => sum + (a.originalSize ?? 0), 0);

  const manifest = {
    version,
    pack: PACK_NAME,
    minAppVersion: args.minAppVersion,
    generatedAt: new Date().toISOString(),
    totalBytes,
    assets: assets.map((a) => ({
      ...a,
      file: `${version}/${a.file}`, // published under a version-prefixed key
    })),
  };

  await writeFile(
    path.join(outDir, 'manifest.json'),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
  await writeFile(
    path.join(outDir, 'ATTRIBUTION.md'),
    renderAttribution(attribution),
  );

  const byType = assets.reduce(
    (acc, a) => ({ ...acc, [a.type]: (acc[a.type] ?? 0) + 1 }),
    {},
  );

  console.log('\n── pack built ───────────────────────────────');
  console.log(`  version        ${version}`);
  console.log(`  categories     ${byType.category ?? 0}`);
  console.log(`  subcategories  ${byType.subcategory ?? 0}`);
  console.log(`  assets total   ${assets.length}`);
  console.log(
    `  original size  ${(originalBytes / 1024 / 1024).toFixed(2)} MB`,
  );
  console.log(
    `  optimized size ${(totalBytes / 1024 / 1024).toFixed(2)} MB` +
      (originalBytes
        ? `  (${Math.round((1 - totalBytes / originalBytes) * 100)}% smaller)`
        : ''),
  );
  console.log(`  output         ${outDir}`);
  console.log(`  elapsed        ${((Date.now() - started) / 1000).toFixed(1)}s`);
  console.log('──────────────────────────────────────────────\n');

  const report = {
    version,
    dir: outDir,
    manifest,
    attribution,
    totalBytes,
    originalBytes,
  };

  if (args.upload && !args.dryRun) {
    const { uploadPack } = await import('./upload-pack.mjs');
    await uploadPack(report);
  } else if (args.upload) {
    console.log('[dry-run] upload skipped');
  }

  return report;
}

async function nextVersion(outRoot) {
  // Version must increase monotonically: the app compares it numerically and
  // only ever offers "newer than installed".
  if (!existsSync(outRoot)) return 1;
  const { readdir } = await import('node:fs/promises');
  const versions = (await readdir(outRoot, { withFileTypes: true }))
    .filter((e) => e.isDirectory() && /^\d+$/.test(e.name))
    .map((e) => Number(e.name));
  return versions.length ? Math.max(...versions) + 1 : 1;
}

function renderAttribution(rows) {
  const lines = [
    '# Category Artwork Pack — attribution',
    '',
    'Every image in this pack was sourced under a licence that permits commercial',
    'use and redistribution. Licences are recorded per file below; keep this file',
    'with the pack.',
    '',
  ];
  for (const r of rows.sort((a, b) => a.id.localeCompare(b.id))) {
    lines.push(`## ${r.id}`);
    lines.push(`- file: \`${r.out}\``);
    lines.push(`- type: ${r.type}`);
    if (r.categoryId) lines.push(`- category: \`${r.categoryId}\``);
    lines.push(`- source: ${r.sourceSite} — ${r.sourceUrl}`);
    lines.push(`- licence: ${r.license}${r.licenseVersion ? ` ${r.licenseVersion}` : ''}`);
    if (r.creator) lines.push(`- creator: ${r.creator}`);
    if (r.attributionRequired && r.attributionText) {
      lines.push(`- attribution text: ${r.attributionText}`);
    }
    lines.push(
      `- optimised: ${r.originalWidth}x${r.originalHeight} ` +
        `(${Math.round((r.originalSize ?? 0) / 1024)} KB) → ` +
        `${r.width}x${r.height} (${Math.round(r.size / 1024)} KB)`,
    );
    lines.push('');
  }
  return `${lines.join('\n')}\n`;
}

try {
  const args = parseArgs(process.argv.slice(2));
  await build(args);
} catch (e) {
  console.error(`\nbuild-pack failed: ${e.message}\n`);
  process.exit(1);
}