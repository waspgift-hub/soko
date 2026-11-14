#!/usr/bin/env node
'use strict';

/**
 * High-signal secret scan over files tracked by git.
 *
 * Scope and limits, stated up front so a green run is not over-read:
 *
 *   * Only tracked files are scanned. `.env`, `CREDENTIALS.txt` and `*.jks` are
 *     gitignored, so a developer's working copy is not inspected — this gate
 *     exists to stop a secret from being *committed*, which is when it becomes
 *     permanent history.
 *   * Patterns are deliberately narrow (provider-prefixed tokens, private key
 *     blocks, high-entropy assignments to credential-looking names). Broad
 *     entropy scanning produces findings nobody triages, which is how real
 *     findings get ignored.
 *   * Firebase web API keys (`AIza...`) are public identifiers, not secrets,
 *     and appear legitimately in `firebase_options.dart`; they are not matched.
 *
 * Exit code 1 on any finding. Run locally with `npm run security:secrets`.
 */

const { execFileSync } = require('child_process');

const ROOT = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();

const PATTERNS = [
  { name: 'private key block', re: /-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----/ },
  { name: 'AWS access key id', re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: 'GitHub token', re: /\bgh[pousr]_[0-9A-Za-z]{36,}\b/ },
  { name: 'Slack token', re: /\bxox[baprs]-[0-9A-Za-z-]{10,}\b/ },
  { name: 'Stripe live key', re: /\bsk_live_[0-9A-Za-z]{20,}\b/ },
  { name: 'Google service account key', re: /"type"\s*:\s*"service_account"[\s\S]{0,400}?"private_key"\s*:\s*"-----BEGIN/ },
  // A DB URL that embeds a password: scheme://user:password@host
  { name: 'credentialed connection string', re: /\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp):\/\/[^\s:@/'"]+:[^\s@/'"]{8,}@/ },
  // Assignment-style secrets. The value must look like a real secret (long and
  // mixed-case/alnum), which keeps Swahili prose and placeholders out.
  {
    name: 'hard-coded credential assignment',
    re: /\b(?:api[_-]?secret|client[_-]?secret|secret[_-]?key|private[_-]?key|access[_-]?token|auth[_-]?token)\b\s*[:=]\s*['"]([A-Za-z0-9_\-+/=]{24,})['"]/i,
  },
];

// Files whose whole job is to hold example/placeholder values.
const ALLOWLIST = [
  /(^|\/)\.env\.example$/,
  /(^|\/)\.env\.sample$/,
  /(^|\/)example[^/]*\.(?:js|ts|dart|json|yaml|yml)$/i,
];

// Binary/lock/vendor paths that would only add noise.
const SKIP = [
  /(^|\/)node_modules\//,
  /(^|\/)package-lock\.json$/,
  /(^|\/)pubspec\.lock$/,
  /(^|\/)\.dart_tool\//,
  /(^|\/)build\//,
  /\.(?:png|jpe?g|gif|webp|ico|pdf|zip|apk|aab|jks|keystore|ttf|otf|woff2?)$/i,
];

function isAllowed(file) {
  return ALLOWLIST.some((re) => re.test(file));
}

function isSkipped(file) {
  return SKIP.some((re) => re.test(file));
}

const files = execFileSync('git', ['ls-files', '-z'], { cwd: ROOT, encoding: 'utf8' })
  .split('\0')
  .filter(Boolean);

const findings = [];
let scanned = 0;

for (const file of files) {
  if (isSkipped(file) || isAllowed(file)) continue;

  let text;
  try {
    text = require('fs').readFileSync(`${ROOT}/${file}`, 'utf8');
  } catch (_) {
    continue;
  }
  // Cheap binary check: NUL byte means the file is not text.
  if (text.includes('\0')) continue;
  scanned += 1;

  const lines = text.split(/\r?\n/);
  for (const { name, re } of PATTERNS) {
    lines.forEach((line, index) => {
      // Skip obvious placeholder shapes even outside allowlisted files.
      if (/['"](?:x{8,}|<[^>]+>|YOUR[_-][A-Z_]+|CHANGEME|PLACEHOLDER|example|dummy|test)['"]/i.test(line)) {
        return;
      }
      if (re.test(line)) {
        findings.push({ file, line: index + 1, name });
      }
    });
  }
}

if (findings.length > 0) {
  console.error(`security:secrets: ${findings.length} finding(s) in ${scanned} tracked files\n`);
  for (const f of findings) {
    console.error(`  ${f.file}:${f.line}  ${f.name}`);
  }
  console.error('\nRemove the value, rotate the credential, and purge it from history.');
  process.exit(1);
}

console.log(`security:secrets: ${scanned} tracked files, no credential patterns found`);
