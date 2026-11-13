// Stages ONLY our own added lines in a file another agent also has uncommitted
// changes in.
//
// `git add -p` is interactive and unavailable here, and `git add <file>` would
// sweep up their work under our commit message. So: build HEAD's content plus our
// additions, stage that, then put the full working-tree file back so their
// changes stay unstaged.
//
// Everything is done in Node with Buffers. The previous attempt used PowerShell
// Out-File/Get-Content, which re-encodes UTF-8 as ANSI and would have turned every
// TSh and euro sign in this file into mojibake.
//
// Usage: node tools/stage-own-lines.cjs <repo-relative-path> <spec.json>
// spec.json: { "after": ["<exact existing line>", ...], "lines": ["...", ...] }
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const repoRoot = path.join(__dirname, '..', '..');
const [relPath, specPath] = process.argv.slice(2);
if (!relPath || !specPath) {
  console.error('usage: node tools/stage-own-lines.cjs <path> <spec.json>');
  process.exit(1);
}

const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const abs = path.join(repoRoot, relPath);

// Buffers throughout: never let a shell re-encode this.
const workingBefore = fs.readFileSync(abs);
const headBefore = execFileSync('git', ['show', `HEAD:${relPath}`], {
  cwd: repoRoot,
  maxBuffer: 64 * 1024 * 1024,
});

const headText = headBefore.toString('utf8');
const hadFinalNewline = headText.endsWith('\n');
const headLines = headText.replace(/\n$/, '').split('\n');

// Insert `lines` after the first line matching each anchor. Anchors are matched
// per-language so the Swahili block and the English block each get their copy.
const out = [];
let inserted = 0;
const anchors = spec.after || [];
const pending = new Map(); // anchor -> lines to insert after it

for (const group of anchors) {
  for (const anchor of group.match) {
    pending.set(anchor, group.lines);
  }
}

for (const line of headLines) {
  out.push(line);
  const add = pending.get(line.trim());
  if (add) {
    for (const l of add) out.push(l);
    pending.delete(line.trim());
    inserted++;
  }
}

if (inserted !== anchors.length) {
  console.error(`ERROR: matched ${inserted} of ${anchors.length} anchors. Nothing staged.`);
  const missing = anchors.filter((g) => !headLines.some((l) => l.trim() === g.match));
  missing.forEach((m) => console.error(`  anchor not found: ${m.match}`));
  process.exit(1);
}

const staged = Buffer.from(out.join('\n') + (hadFinalNewline ? '\n' : ''), 'utf8');

try {
  fs.writeFileSync(abs, staged);
  execFileSync('git', ['add', '--', relPath], { cwd: repoRoot });
  console.log(`staged ${inserted} anchor group(s), ${spec.after[0].lines.length} lines each`);
} finally {
  // Always put their version back, even if staging failed.
  fs.writeFileSync(abs, workingBefore);
}

const stagedDiff = execFileSync('git', ['diff', '--cached', '--', relPath], {
  cwd: repoRoot,
  maxBuffer: 64 * 1024 * 1024,
}).toString('utf8');
const added = stagedDiff.split('\n').filter((l) => l.startsWith('+') && !l.startsWith('+++'));
const removed = stagedDiff.split('\n').filter((l) => l.startsWith('-') && !l.startsWith('---'));
console.log(`staged diff: +${added.length} -${removed.length}`);
if (removed.length) {
  console.log('WARNING: staged diff also removes lines.');
  removed.forEach((l) => console.log('  ' + l));
}
