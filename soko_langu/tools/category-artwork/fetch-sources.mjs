#!/usr/bin/env node
/**
 * Soko Vibe — fetch licensed category artwork.
 *
 *   node tools/category-artwork/fetch-sources.mjs --query electronics "smartphone" --id electronics --type category
 *   node tools/category-artwork/fetch-sources.mjs --from-commons --id electronics --type category --search "consumer electronics"
 *   node tools/category-artwork/fetch-sources.mjs --batch electronics=phones,laptops
 *
 * Downloads only licence-approved imagery from APIs that state their terms
 * machine-readably, and records the provenance in SOURCES.json so the pack
 * build can prove it.
 *
 * Licence policy (enforced, not advisory): CC0 / Public Domain Mark only.
 * CC-BY / CC-BY-SA are rejected on purpose — BY-SA would impose ShareAlike on
 * the pack's own derivative WebP output and require attribution baked into the
 * artwork. If commercial-use attribution becomes acceptable, widen
 * ALLOWED_LICENSES in build-pack.mjs rather than silently accepting it here.
 *
 * Provenance, not legality, is the real limit: free-licensed photo search
 * returns subject-matter matches, not art-directed category tiles. Every fetch
 * writes a candidate that a human must review before it ships. `--accept`
 * skips that review and is for bulk licensed-enough material only.
 */

import { createWriteStream } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RAW_DIR = path.join(__dirname, 'sources', 'raw');
const SOURCES_FILE = path.join(__dirname, 'sources', 'SOURCES.json');

const ALLOWED = new Set(['cc0', 'pdm', 'publicdomain']);
const OPENVERSE = 'https://api.openverse.org/v1/images/';
const COMMONS_API = 'https://commons.wikimedia.org/w/api.php';

// Downloads are small (one photo at a time) but a slow link must not hang the
// pipeline forever.
const FETCH_TIMEOUT_MS = 45_000;

function parseArgs(argv) {
  const args = {
    id: null,
    type: 'category',
    categoryId: null,
    query: null,
    search: null,
    fromCommons: false,
    accept: false,
    limit: 1,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--id') args.id = argv[++i];
    else if (a === '--type') args.type = argv[++i];
    else if (a === '--category-id') args.categoryId = argv[++i];
    else if (a === '--query') args.query = argv[++i];
    else if (a === '--search') args.search = argv[++i];
    else if (a === '--from-commons') args.fromCommons = true;
    else if (a === '--accept') args.accept = true;
    else if (a === '--limit') args.limit = Number(argv[++i]);
    else throw new Error(`Unknown flag: ${a}`);
  }
  if (!args.id) throw new Error('--id is required');
  if (args.type === 'subcategory' && !args.categoryId) {
    throw new Error('--category-id is required for --type subcategory');
  }
  return args;
}

function normaliseLicense(raw) {
  return String(raw ?? '').toLowerCase().trim().replace(/^cc0-/, 'cc0');
}

async function searchOpenverse(query, limit) {
  const url = new URL(OPENVERSE);
  url.searchParams.set('q', query);
  url.searchParams.set('license', 'cc0,pdm');
  url.searchParams.set('size', 'medium');
  url.searchParams.set('page_size', String(limit));
  const res = await fetch(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
  if (!res.ok) throw new Error(`Openverse search failed: HTTP ${res.status}`);
  const json = await res.json();
  return (json.results ?? []).map((r) => ({
    id: r.id,
    title: r.title,
    url: r.url,
    thumbnail: r.thumbnail,
    foreign_landing_url: r.foreign_landing_url,
    creator: r.creator,
    license: normaliseLicense(r.license),
    licenseVersion: r.license_version,
    sourceSite: r.foreign_landing_url ? new URL(r.foreign_landing_url).hostname : 'openverse',
    width: r.width,
    height: r.height,
    provider: 'openverse',
  }));
}

/**
 * Wikimedia Commons search, restricted to files whose licence template is on the
 * allow list. Commons states licensing per file in `extmetadata`, which is why
 * it is preferred over a general web scrape.
 */
async function searchCommons(search, limit) {
  const url = new URL(COMMONS_API);
  url.searchParams.set('action', 'query');
  url.searchParams.set('format', 'json');
  url.searchParams.set('generator', 'search');
  url.searchParams.set(
    'gsrsearch',
    `filetype:bitmap ${search}`,
  );
  url.searchParams.set('gsrnamespace', '6');
  url.searchParams.set('gsrlimit', String(Math.max(limit * 4, 10)));
  url.searchParams.set('prop', 'imageinfo');
  url.searchParams.set('iiprop', 'url|size|extmetadata');
  url.searchParams.set('iiurlwidth', '1200');

  const res = await fetch(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
  if (!res.ok) throw new Error(`Commons search failed: HTTP ${res.status}`);
  const json = await res.json();
  const pages = Object.values(json?.query?.pages ?? {});

  const out = [];
  for (const p of pages) {
    const info = p.imageinfo?.[0];
    const meta = info?.extmetadata ?? {};
    const license = normaliseLicense(meta.LicenseShortName?.value);
    if (!ALLOWED.has(license)) continue;
    if (!info?.thumburl) continue;
    out.push({
      id: p.title,
      title: p.title.replace(/^File:/, ''),
      url: info.thumburl,
      foreign_landing_url: info.descriptionurl,
      creator: stripHtml(meta.Artist?.value ?? ''),
      license,
      licenseVersion: meta.LicenseVersion?.value ?? null,
      sourceSite: 'commons.wikimedia.org',
      width: meta.ImageWidth?.value ?? info.thumbwidth,
      height: meta.ImageHeight?.value ?? info.thumbheight,
      attributionText: meta.AttributionRequired?.value
        ? stripHtml(meta.UsageTerms?.value ?? '')
        : null,
      provider: 'wikimedia-commons',
    });
    if (out.length >= limit) break;
  }
  return out;
}

function stripHtml(s) {
  return String(s ?? '')
    .replace(/<[^>]*>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

async function download(url, destFile) {
  const res = await fetch(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
  if (!res.ok) throw new Error(`Download failed: HTTP ${res.status}`);
  const type = res.headers.get('content-type') ?? '';
  if (!type.startsWith('image/')) {
    throw new Error(`Refusing non-image response (${type}) from ${url}`);
  }
  await mkdir(path.dirname(destFile), { recursive: true });
  await pipeline(Readable.fromWeb(res.body), createWriteStream(destFile));
  return (await import('node:fs/promises')).stat(destFile).then((s) => s.size);
}

function extFor(url) {
  try {
    const ext = path.extname(new URL(url).pathname).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.webp'].includes(ext)) return ext;
  } catch {}
  return '.jpg';
}

async function record(entry) {
  const raw = existsSync(SOURCES_FILE)
    ? JSON.parse(await readFile(SOURCES_FILE, 'utf8'))
    : { sources: [] };
  raw.sources = raw.sources.filter((s) => s.id !== entry.id || s.type !== entry.type);
  raw.sources.push(entry);
  await writeFile(SOURCES_FILE, `${JSON.stringify(raw, null, 2)}\n`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const searchTerm = args.query ?? args.search ?? args.id;

  const candidates = args.fromCommons
    ? await searchCommons(searchTerm, args.limit)
    : await searchOpenverse(searchTerm, args.limit);

  if (candidates.length === 0) {
    throw new Error(
      `No licence-approved candidate for "${searchTerm}". ` +
        'Try a different term or --from-commons.',
    );
  }

  console.log(`\ncandidates for "${searchTerm}" (${candidates.length}):`);
  candidates.forEach((c, i) => {
    console.log(
      `  [${i}] ${c.license}${c.licenseVersion ? ` ${c.licenseVersion}` : ''}  ` +
        `${c.width}x${c.height}  ${c.title}`,
    );
  });

  const pick = candidates[0];
  if (!args.accept && candidates.length > 1) {
    console.log(
      '\nNot auto-accepting. Re-run with the chosen index appended as a source ' +
        'file check, or pass --accept if this category only needs one licensed image.',
    );
  }

  const fileName = `${args.type}-${args.id}${extFor(pick.url)}`;
  const dest = path.join(RAW_DIR, fileName);
  const size = await download(pick.url, dest);

  const entry = {
    id: args.id,
    type: args.type,
    ...(args.categoryId ? { categoryId: args.categoryId } : {}),
    file: path.relative(path.dirname(SOURCES_FILE), dest).replace(/\\/g, '/'),
    sourceUrl: pick.foreign_landing_url ?? pick.url,
    downloadUrl: pick.url,
    sourceSite: pick.sourceSite,
    license: pick.license,
    licenseVersion: pick.licenseVersion,
    creator: pick.creator,
    attributionRequired: Boolean(pick.attributionText),
    attributionText: pick.attributionText ?? undefined,
    title: pick.title,
    bytes: size,
    reviewed: args.accept,
  };

  await record(entry);

  console.log(`\nsaved  ${dest}`);
  console.log(`       ${(size / 1024).toFixed(0)} KB  ${pick.license}`);
  console.log(`       source: ${entry.sourceUrl}`);
  console.log(
    args.accept
      ? '       marked reviewed (--accept)'
      : '       REVIEW THIS IMAGE before running build-pack.mjs — free-licensed search\n' +
          '       finds subject matches, not art-directed category art.',
  );
  console.log('');
}

main().catch((e) => {
  console.error(`\nfetch-sources failed: ${e.message}\n`);
  process.exit(1);
});