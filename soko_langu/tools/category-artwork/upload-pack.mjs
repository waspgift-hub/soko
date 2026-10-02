#!/usr/bin/env node
/**
 * Uploads a built Category Artwork Pack to Cloudflare R2 using wrangler, so no
 * S3-compatible API token is required — wrangler's existing login is enough.
 *
 *   node tools/category-artwork/upload-pack.mjs --version 1
 *
 * Objects are written to `artwork/<version>/...`, which the `soko-media`
 * Worker's `artwork` prefix maps to the public `soko-vibe-artwork` bucket.
 * Versioned keys make every object immutable, so the CDN can serve
 * `max-age=1y` while `artwork/manifest.json` stays revalidatable.
 *
 * Order matters: assets first, manifest last. A client that polls the
 * version-agnostic `artwork/manifest.json` can therefore never observe a
 * manifest whose files are not yet in the bucket.
 */

import { readFile, readdir, stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const BUCKET = process.env.R2_ARTWORK_BUCKET ?? 'soko-vibe-artwork';

const require = createRequire(import.meta.url);

// wrangler's package.json restricts `exports`, so its bin path cannot be
// resolved through require.resolve. Read the package location and join the
// well-known entry instead.
const WRANGLER_ENTRY = path.join(
  path.dirname(require.resolve('wrangler/package.json')),
  'bin',
  'wrangler.js',
);

function parseArgs(argv) {
  const args = { version: null, outRoot: path.join(REPO_ROOT, 'build', 'category-artwork') };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--version') args.version = Number(argv[++i]);
    else if (argv[i] === '--out') args.outRoot = path.resolve(argv[++i]);
    else throw new Error(`Unknown flag: ${argv[i]}`);
  }
  if (!args.version) throw new Error('--version is required');
  return args;
}

/**
 * Runs the local wrangler CLI.
 *
 * Invoked as `node <wrangler entry>` rather than `npx wrangler`: on Windows
 * `npx` is a .cmd shim, so it must be spawned through a shell, and a shell then
 * re-splits any argument containing a space — which every path in this project
 * does. Spawning node directly keeps arguments intact on all platforms.
 */
function run(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [WRANGLER_ENTRY, ...args], {
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false,
    });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (out += d));
    child.on('error', reject);
    child.on('close', (code) =>
      code === 0
        ? resolve(out)
        : reject(new Error(`wrangler exited ${code}: ${out.slice(-400)}`)),
    );
  });
}

async function walk(dir, base = '') {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const rel = base ? `${base}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...(await walk(full, rel)));
    else out.push({ full, rel });
  }
  return out;
}

function contentTypeFor(key) {
  if (key.endsWith('.webp')) return 'image/webp';
  if (key.endsWith('.json')) return 'application/json';
  if (key.endsWith('.md')) return 'text/markdown; charset=utf-8';
  return 'application/octet-stream';
}

async function put(key, file) {
  await run([
    'r2', 'object', 'put', `${BUCKET}/${key}`,
    '--file', file,
    '--content-type', contentTypeFor(key),
    '--remote',
  ]);
}

async function upload({ version, outRoot }) {
  const packDir = path.join(outRoot, String(version));
  const manifest = JSON.parse(await readFile(path.join(packDir, 'manifest.json'), 'utf8'));

  console.log(`\n── uploading pack v${version} to ${BUCKET} ──`);

  let bytes = 0;
  let n = 0;
  for (const asset of manifest.assets) {
    // manifest.file is already `artwork/<version>/<rel>` shape (version-prefixed).
    const rel = asset.file.replace(/^\d+\//, '');
    const file = path.join(packDir, rel.replaceAll('/', path.sep));
    bytes += (await stat(file)).size;
    // asset.file is version-relative (`1/categories/x.webp`); the bucket key
    // needs the artwork/ prefix that the Worker's bucket selector reads.
    await put(`artwork/${asset.file}`, file);
    n++;
    if (n % 10 === 0) console.log(`  ${n}/${manifest.assets.length} assets`);
  }

  await put(`artwork/${version}/ATTRIBUTION.md`, path.join(packDir, 'ATTRIBUTION.md'));
  // Manifest last: its presence is the signal that everything else is there.
  await put(`artwork/${version}/manifest.json`, path.join(packDir, 'manifest.json'));
  await put('artwork/manifest.json', path.join(packDir, 'manifest.json'));

  console.log(`  ${n} assets, ${(bytes / 1024 / 1024).toFixed(2)} MB`);
  console.log('  manifest: https://media.sokovibe.co.tz/artwork/manifest.json');
  console.log('──────────────────────────────────────────────\n');
}

try {
  await upload(parseArgs(process.argv.slice(2)));
} catch (e) {
  console.error(`\nupload failed: ${e.message}\n`);
  process.exit(1);
}