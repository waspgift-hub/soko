#!/usr/bin/env node
'use strict';

/**
 * Dependency-free backend lint gate.
 *
 * The repo has no ESLint install and no ESLint config, so `npm run lint` used to
 * spawn `eslint src/` and fail with "command not found" on every machine — a
 * green check that never ran. This script is what CI can actually enforce until
 * a real linter is added, and it checks the two failure modes that have already
 * broken production bundles here:
 *
 *   1. A file under `src/` that does not parse. Caught at boot normally, but a
 *      syntax error inside a lazily-required module only surfaces on the code
 *      path that requires it (e.g. the escrow cron), so it is checked eagerly.
 *   2. A `require('./relative/path')` whose target does not exist. Renaming or
 *      moving a module leaves a call site that throws MODULE_NOT_FOUND at
 *      runtime; that is exactly how the legacy order-transition call shipped
 *      against a function that had been removed.
 *
 * Deliberately not a style checker: line length, quotes and spacing are review
 * concerns and would produce a diff-only rule nobody acts on.
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SRC = path.resolve(__dirname, '..', 'src');
const errors = [];

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (entry.isFile() && entry.name.endsWith('.js')) {
      out.push(full);
    }
  }
  return out;
}

function rel(file) {
  return path.relative(path.resolve(__dirname, '..'), file).replace(/\\/g, '/');
}

// Comments are removed before the require scan, because documentation that
// shows the correct call shape (`* require('../src/config/redis')`) is not an
// import and must not be reported as one. A small tokenizer is used instead of
// a regex so a `//` inside a URL string, or a require inside a block comment,
// cannot skew the result.
function stripComments(src) {
  let out = '';
  let i = 0;
  let state = 'code';
  const n = src.length;

  while (i < n) {
    const c = src[i];
    const d = src[i + 1];

    if (state === 'code') {
      if (c === '/' && d === '/') { state = 'line'; i += 2; continue; }
      if (c === '/' && d === '*') { state = 'block'; i += 2; out += ' '; continue; }
      if (c === "'") { state = 'single'; out += c; i += 1; continue; }
      if (c === '"') { state = 'double'; out += c; i += 1; continue; }
      if (c === '`') { state = 'template'; out += c; i += 1; continue; }
      out += c; i += 1; continue;
    }

    if (state === 'line') {
      if (c === '\n') { state = 'code'; out += c; }
      i += 1; continue;
    }

    if (state === 'block') {
      if (c === '*' && d === '/') { state = 'code'; i += 2; continue; }
      if (c === '\n') out += '\n';
      i += 1; continue;
    }

    if (c === '\\') { out += c + (d || ''); i += 2; continue; }
    if (
      (state === 'single' && c === "'") ||
      (state === 'double' && c === '"') ||
      (state === 'template' && c === '`')
    ) {
      state = 'code';
    }
    out += c; i += 1;
  }

  return out;
}

// A require target may be a directory with an index.js, or omit the extension.
function resolves(fromFile, spec) {
  const base = path.resolve(path.dirname(fromFile), spec);
  const candidates = [
    base,
    `${base}.js`,
    `${base}.json`,
    path.join(base, 'index.js'),
    path.join(base, 'index.json'),
  ];
  return candidates.some((candidate) => {
    try {
      return fs.statSync(candidate).isFile();
    } catch (_) {
      return false;
    }
  });
}

const files = walk(SRC);
const REQUIRE_RE = /require\(\s*['"](\.[^'"]*)['"]\s*\)/g;

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const parsed = raw.replace(/^#!.*/, '');

  // vm.Script parses as a classic script (same grammar as CommonJS modules) and
  // throws with the offending line on a syntax error. The shebang is stripped
  // first: Node tolerates it, the vm parser does not. Parsing uses the raw text
  // (regex literals would trip the comment stripper); only the require scan uses
  // the comment-free copy.
  try {
    new vm.Script(parsed, { filename: file });
  } catch (e) {
    errors.push(`${rel(file)}: does not parse — ${e.message}`);
    continue;
  }

  const source = stripComments(parsed);

  if (/^\s*debugger\s*;?\s*$/m.test(source)) {
    errors.push(`${rel(file)}: contains a 'debugger' statement`);
  }

  let match;
  REQUIRE_RE.lastIndex = 0;
  while ((match = REQUIRE_RE.exec(source)) !== null) {
    const spec = match[1];
    if (!resolves(file, spec)) {
      errors.push(`${rel(file)}: require('${spec}') does not resolve to a file`);
    }
  }
}

if (errors.length > 0) {
  console.error(`lint: ${errors.length} problem(s) in ${files.length} files\n`);
  for (const line of errors) console.error(`  ${line}`);
  process.exit(1);
}

console.log(`lint: ${files.length} files parse and every relative require resolves`);
